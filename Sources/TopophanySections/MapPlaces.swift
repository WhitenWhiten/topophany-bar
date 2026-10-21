import Foundation

/// Where a place is, as its name says, for a map drawn without `map.graph`:
/// the places `servers.list` names, nothing else. Like a place's time zone
/// (PlaceZones), this is never evidence, only where to draw a mark `topo`
/// sent.
public enum MapPlaces {
    /// The place's coordinates: a city of `topo`'s gazetteer, the one its
    /// editor fills a node's location from, else the city a time zone is
    /// named for, where the time zone database puts it. Nil when the name
    /// is no city, as for "anycast" or "Home".
    public static func coordinate(for place: String) -> MapSection.Coordinate? {
        if let c = PlaceZones.lookup(place, in: gazetteerTable) { return c }
        return PlaceZones.suggestion(for: place).flatMap { zones[$0] }
    }

    /// `topo`'s gazetteer (the TUI editor's place lookup), in English and
    /// Chinese as `topo` spells them, and Japanese.
    static let gazetteer: [([String], Double, Double)] = [
        (["Shanghai", "上海"], 31.23, 121.47), (["Beijing", "北京"], 39.9, 116.4), (["Hangzhou", "杭州"], 30.27, 120.15),
        (["Shenzhen", "深圳", "深セン"], 22.54, 114.06), (["Guangzhou", "广州", "広州"], 23.13, 113.26),
        (["Chengdu", "成都"], 30.66, 104.07), (["Nanjing", "南京"], 32.06, 118.8), (["Wuhan", "武汉", "武漢"], 30.59, 114.3),
        (["Qingdao", "青岛", "青島"], 36.07, 120.38), (["Zhangjiakou", "张家口", "張家口"], 40.77, 114.88),
        (["Ulanqab", "乌兰察布", "ウランチャブ"], 41.03, 113.13), (["Hong Kong", "香港"], 22.32, 114.17),
        (["Taipei", "台北"], 25.03, 121.57), (["Tokyo", "东京", "東京"], 35.68, 139.69), (["Osaka", "大阪"], 34.69, 135.5),
        (["Seoul", "首尔"], 37.57, 126.98), (["Singapore", "新加坡"], 1.35, 103.82), (["Kuala Lumpur", "吉隆坡"], 3.14, 101.69),
        (["Jakarta", "雅加达"], -6.2, 106.85), (["Bangkok", "曼谷"], 13.76, 100.5), (["Manila", "马尼拉"], 14.6, 120.98),
        (["Mumbai", "孟买", "ムンバイ"], 19.08, 72.88), (["Sydney", "悉尼"], -33.87, 151.21), (["Melbourne", "墨尔本"], -37.81, 144.96),
        (["Auckland", "奥克兰"], -36.85, 174.76), (["Dubai", "迪拜"], 25.2, 55.27), (["Istanbul", "伊斯坦布尔"], 41.01, 28.98),
        (["Moscow", "莫斯科"], 55.76, 37.62), (["Frankfurt", "法兰克福", "フランクフルト"], 50.11, 8.68),
        (["Amsterdam", "阿姆斯特丹"], 52.37, 4.9), (["London", "伦敦"], 51.51, -0.13), (["Paris", "巴黎"], 48.86, 2.35),
        (["Dublin", "都柏林"], 53.35, -6.26), (["Stockholm", "斯德哥尔摩"], 59.33, 18.07), (["Helsinki", "赫尔辛基"], 60.17, 24.94),
        (["Warsaw", "华沙"], 52.23, 21.01), (["Zurich", "苏黎世"], 47.38, 8.54), (["Milan", "米兰", "ミラノ"], 45.46, 9.19),
        (["Madrid", "马德里"], 40.42, -3.7), (["Johannesburg", "约翰内斯堡"], -26.2, 28.05), (["Lagos", "拉各斯"], 6.52, 3.38),
        (["Cairo", "开罗"], 30.04, 31.24), (["Ashburn", "阿什本", "アッシュバーン"], 39.04, -77.49),
        (["Virginia", "弗吉尼亚", "バージニア"], 38.95, -77.45), (["New York", "纽约"], 40.71, -74.01),
        (["Chicago", "芝加哥"], 41.88, -87.63), (["Dallas", "达拉斯", "ダラス"], 32.78, -96.8),
        (["Atlanta", "亚特兰大", "アトランタ"], 33.75, -84.39), (["Miami", "迈阿密", "マイアミ"], 25.76, -80.19),
        (["Toronto", "多伦多"], 43.65, -79.38), (["Montreal", "蒙特利尔", "モントリオール"], 45.5, -73.57),
        (["Los Angeles", "洛杉矶"], 34.05, -118.24), (["San Jose", "圣何塞", "サンノゼ"], 37.34, -121.89),
        (["San Francisco", "旧金山", "サンフランシスコ"], 37.77, -122.42), (["Fremont", "弗里蒙特", "フリーモント"], 37.55, -121.99),
        (["Seattle", "西雅图", "シアトル"], 47.61, -122.33), (["Portland", "波特兰", "ポートランド"], 45.52, -122.68),
        (["Phoenix", "凤凰城"], 33.45, -112.07), (["Mexico City", "墨西哥城"], 19.43, -99.13), (["São Paulo", "圣保罗"], -23.55, -46.63),
        (["Santiago", "圣地亚哥"], -33.45, -70.67), (["Buenos Aires", "布宜诺斯艾利斯"], -34.6, -58.38),
    ]

    static let gazetteerTable: [String: MapSection.Coordinate] = {
        var t: [String: MapSection.Coordinate] = [:]
        for (names, lat, lon) in gazetteer {
            for n in names { t[PlaceZones.fold(n)] = MapSection.Coordinate(lat: lat, lon: lon) }
        }
        return t
    }()

    /// Each time zone's city, where the system's zone.tab puts it.
    static let zones: [String: MapSection.Coordinate] = {
        guard let text = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return [:] }
        return zoneTable(text)
    }()

    /// zone.tab's lines: country, ISO 6709 coordinates (±DDMM±DDDMM or
    /// ±DDMMSS±DDDMMSS), zone.
    static func zoneTable(_ text: String) -> [String: MapSection.Coordinate] {
        var t: [String: MapSection.Coordinate] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let f = line.split(separator: "\t")
            guard f.count >= 3, let c = iso6709(String(f[1])) else { continue }
            t[String(f[2])] = c
        }
        return t
    }

    static func iso6709(_ s: String) -> MapSection.Coordinate? {
        guard let split = s.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func degrees(_ part: Substring, _ degreeDigits: Int) -> Double? {
            guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
            let digits = part.dropFirst()
            guard digits.allSatisfy(\.isNumber), digits.count == degreeDigits + 2 || digits.count == degreeDigits + 4 else { return nil }
            let d = Double(digits.prefix(degreeDigits)) ?? 0
            let m = Double(digits.dropFirst(degreeDigits).prefix(2)) ?? 0
            let sec = digits.count > degreeDigits + 2 ? Double(digits.suffix(2)) ?? 0 : 0
            return (sign == "-" ? -1 : 1) * (d + m / 60 + sec / 3600)
        }
        guard let lat = degrees(s[s.startIndex..<split], 2), let lon = degrees(s[split...], 3) else { return nil }
        return MapSection.Coordinate(lat: lat, lon: lon)
    }
}
