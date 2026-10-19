import Foundation

/// The time zone for a place, as `topo` names it (`where`: the topology's
/// own label). A zone is only a clock for the Time zones section, never
/// evidence: it is the user's choice, or what the place's name suggests.
public enum PlaceZones {
    /// The zone for `place`: the one chosen for it, else the one its name
    /// suggests. A choice of "" means none.
    public static func zone(for place: String, chosen: [String: String]) -> TimeZone? {
        if let c = chosen[place] { return c.isEmpty ? nil : TimeZone(identifier: c) }
        return suggestion(for: place).flatMap(TimeZone.init(identifier:))
    }

    /// The zone whose city the place names, in English, Japanese or
    /// Chinese: "Tokyo", "東京", "Frankfurt am Main", "Seattle (home)".
    /// Nil when no city matches, as for "anycast" or coordinates.
    public static func suggestion(for place: String) -> String? {
        let key = fold(place)
        guard !key.isEmpty else { return nil }
        if let z = table[key] { return z }
        // The longest city the label starts with, ending at a word's end:
        // "tokyo 2" and "frankfurt am main", never "parisian".
        var best: (String, String)?
        for (city, zone) in table where city.count > (best?.0.count ?? 0) && key.hasPrefix(city) {
            let rest = key.dropFirst(city.count)
            let joined = rest.first.map { $0.isLetter && !isCJK(city.last ?? " ") } ?? false
            if !joined { best = (city, zone) }
        }
        return best?.1
    }

    /// Every IANA zone a place can be given, by region: "America" →
    /// ["America/Los_Angeles", …].
    public static let regions: [(region: String, zones: [String])] = {
        let all = TimeZone.knownTimeZoneIdentifiers.filter { id in prefixes.contains { id.hasPrefix($0 + "/") } }
        return prefixes.compactMap { r in
            let zones = all.filter { $0.hasPrefix(r + "/") }.sorted { city($0) < city($1) }
            return zones.isEmpty ? nil : (r, zones)
        }
    }()

    /// A zone's city in the panel's language: "Los Angeles", "ロサンゼルス".
    public static func city(_ identifier: String, locale: Locale = L10n.locale) -> String {
        guard let tz = TimeZone(identifier: identifier) else { return identifier }
        let f = Date.FormatStyle(locale: locale, timeZone: tz).timeZone(.exemplarLocation)
        let s = Date(timeIntervalSinceReferenceDate: 0).formatted(f)
        return s.isEmpty ? identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier : s
    }

    static let prefixes = ["Africa", "America", "Antarctica", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific"]

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.first.map { (0x3040...0x9FFF).contains($0.value) } ?? false
    }

    /// City name → zone: every zone's own city in English, Japanese and
    /// Chinese, then the cities of `topo`'s gazetteer that no zone is named
    /// for.
    static let table: [String: String] = {
        var t: [String: String] = [:]
        let locales = ["en", "ja", "zh-Hans", "zh-Hant"].map(Locale.init(identifier:))
        for r in regions {
            for id in r.zones {
                for l in locales {
                    let k = fold(city(id, locale: l))
                    if !k.isEmpty, t[k] == nil { t[k] = id }
                }
                if let last = id.split(separator: "/").last {
                    let k = fold(last.replacingOccurrences(of: "_", with: " "))
                    if t[k] == nil { t[k] = id }
                }
            }
        }
        for (names, zone) in gazetteer {
            for n in names { t[fold(n)] = zone }
        }
        return t
    }()

    /// Cities in `topo`'s gazetteer (the TUI's place lookup) whose zone is
    /// named for another city, in English, Chinese as `topo` spells them,
    /// and Japanese.
    static let gazetteer: [([String], String)] = [
        (["Beijing", "北京"], "Asia/Shanghai"),
        (["Hangzhou", "杭州"], "Asia/Shanghai"),
        (["Shenzhen", "深圳", "深セン"], "Asia/Shanghai"),
        (["Guangzhou", "广州", "広州"], "Asia/Shanghai"),
        (["Chengdu", "成都"], "Asia/Shanghai"),
        (["Nanjing", "南京"], "Asia/Shanghai"),
        (["Wuhan", "武汉", "武漢"], "Asia/Shanghai"),
        (["Qingdao", "青岛", "青島"], "Asia/Shanghai"),
        (["Zhangjiakou", "张家口", "張家口"], "Asia/Shanghai"),
        (["Ulanqab", "乌兰察布", "ウランチャブ"], "Asia/Shanghai"),
        (["Osaka", "大阪"], "Asia/Tokyo"),
        (["Mumbai", "孟买", "ムンバイ"], "Asia/Kolkata"),
        (["Frankfurt", "法兰克福", "フランクフルト"], "Europe/Berlin"),
        (["Milan", "米兰", "ミラノ"], "Europe/Rome"),
        (["Ashburn", "阿什本", "アッシュバーン"], "America/New_York"),
        (["Virginia", "弗吉尼亚", "バージニア"], "America/New_York"),
        (["Atlanta", "亚特兰大", "アトランタ"], "America/New_York"),
        (["Miami", "迈阿密", "マイアミ"], "America/New_York"),
        (["Dallas", "达拉斯", "ダラス"], "America/Chicago"),
        (["Montreal", "蒙特利尔", "モントリオール"], "America/Toronto"),
        (["San Jose", "圣何塞", "サンノゼ"], "America/Los_Angeles"),
        (["San Francisco", "旧金山", "サンフランシスコ"], "America/Los_Angeles"),
        (["Fremont", "弗里蒙特", "フリーモント"], "America/Los_Angeles"),
        (["Seattle", "西雅图", "シアトル"], "America/Los_Angeles"),
        (["Portland", "波特兰", "ポートランド"], "America/Los_Angeles"),
    ]
}
