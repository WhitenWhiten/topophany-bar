import Foundation
import Testing
@testable import TopophanySections
import TopophanyEngine
import TopophanyKit

/// A panel whose request lists servers, as the app asks when `topo` can.
func zonesPanel(_ scenario: FixtureEngine.Scenario, here: String = "America/Los_Angeles", listServers: Bool = true,
                change: (inout Settings) -> Void = { _ in }) -> PanelModel {
    var s = settings()
    change(&s)
    let request = TemplateCompiler().request(for: s, revision: 1, listServers: listServers)
    let reading = FixtureEngine.reading(scenario, request: request, origin: origin, after: 4)
    return SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: s, here: TimeZone(identifier: here)!))
}

@Suite struct PlaceZonesTests {
    /// Every city in `topo`'s gazetteer (internal/tui/editor.go), as the
    /// TUI's editor writes it and in `topo`'s Chinese.
    static let gazetteer: [(String, String)] = [
        ("Shanghai", "上海"), ("Beijing", "北京"), ("Hangzhou", "杭州"), ("Shenzhen", "深圳"), ("Guangzhou", "广州"),
        ("Chengdu", "成都"), ("Nanjing", "南京"), ("Wuhan", "武汉"), ("Qingdao", "青岛"), ("Zhangjiakou", "张家口"),
        ("Ulanqab", "乌兰察布"), ("Hong Kong", "香港"), ("Taipei", "台北"), ("Tokyo", "东京"), ("Osaka", "大阪"),
        ("Seoul", "首尔"), ("Singapore", "新加坡"), ("Kuala Lumpur", "吉隆坡"), ("Jakarta", "雅加达"), ("Bangkok", "曼谷"),
        ("Manila", "马尼拉"), ("Mumbai", "孟买"), ("Sydney", "悉尼"), ("Melbourne", "墨尔本"), ("Auckland", "奥克兰"),
        ("Dubai", "迪拜"), ("Istanbul", "伊斯坦布尔"), ("Moscow", "莫斯科"), ("Frankfurt", "法兰克福"), ("Amsterdam", "阿姆斯特丹"),
        ("London", "伦敦"), ("Paris", "巴黎"), ("Dublin", "都柏林"), ("Stockholm", "斯德哥尔摩"), ("Helsinki", "赫尔辛基"),
        ("Warsaw", "华沙"), ("Zurich", "苏黎世"), ("Milan", "米兰"), ("Madrid", "马德里"), ("Johannesburg", "约翰内斯堡"),
        ("Lagos", "拉各斯"), ("Cairo", "开罗"), ("Ashburn", "阿什本"), ("Virginia", "弗吉尼亚"), ("New York", "纽约"),
        ("Chicago", "芝加哥"), ("Dallas", "达拉斯"), ("Atlanta", "亚特兰大"), ("Miami", "迈阿密"), ("Toronto", "多伦多"),
        ("Montreal", "蒙特利尔"), ("Los Angeles", "洛杉矶"), ("San Jose", "圣何塞"), ("San Francisco", "旧金山"),
        ("Fremont", "弗里蒙特"), ("Seattle", "西雅图"), ("Portland", "波特兰"), ("Phoenix", "凤凰城"),
        ("Mexico City", "墨西哥城"), ("São Paulo", "圣保罗"), ("Santiago", "圣地亚哥"), ("Buenos Aires", "布宜诺斯艾利斯"),
    ]

    @Test func everyGazetteerCityHasAZone() {
        for (en, zh) in Self.gazetteer {
            let a = PlaceZones.suggestion(for: en)
            #expect(a != nil, "\(en)")
            #expect(PlaceZones.suggestion(for: zh) == a, "\(zh) and \(en)")
        }
    }

    @Test func zonesForThePreviewNetworks() {
        let expected: [String: String] = [
            "Seattle": "America/Los_Angeles", "San Jose": "America/Los_Angeles", "Los Angeles": "America/Los_Angeles",
            "Honolulu": "Pacific/Honolulu", "New York": "America/New_York", "Frankfurt": "Europe/Berlin", "Tokyo": "Asia/Tokyo",
            "ニューヨーク": "America/New_York", "フランクフルト": "Europe/Berlin", "ホノルル": "Pacific/Honolulu",
            "ロサンゼルス": "America/Los_Angeles", "大阪": "Asia/Tokyo", "東京": "Asia/Tokyo",
            "东京": "Asia/Tokyo", "成都": "Asia/Shanghai", "杭州": "Asia/Shanghai", "檀香山": "Pacific/Honolulu",
            "法兰克福": "Europe/Berlin", "洛杉矶": "America/Los_Angeles", "纽约": "America/New_York",
        ]
        for (place, zone) in expected { #expect(PlaceZones.suggestion(for: place) == zone, "\(place)") }
    }

    @Test func labelsThatOnlyStartWithACity() {
        #expect(PlaceZones.suggestion(for: "Tokyo 2") == "Asia/Tokyo")
        #expect(PlaceZones.suggestion(for: "frankfurt am main") == "Europe/Berlin")
        #expect(PlaceZones.suggestion(for: "Seattle (home)") == "America/Los_Angeles")
        #expect(PlaceZones.suggestion(for: "Sao Paulo") == "America/Sao_Paulo")
        #expect(PlaceZones.suggestion(for: "東京都") == "Asia/Tokyo")
    }

    @Test func placesThatNameNoCity() {
        for place in ["anycast", "on Home Router", "47.6°N 122.3°W", "", "Parisian", "us-east-1"] {
            #expect(PlaceZones.suggestion(for: place) == nil, "\(place)")
        }
    }

    @Test func aChoiceWins() {
        #expect(PlaceZones.zone(for: "Seattle", chosen: ["Seattle": "America/Vancouver"])?.identifier == "America/Vancouver")
        #expect(PlaceZones.zone(for: "Seattle", chosen: ["Seattle": ""]) == nil)
        #expect(PlaceZones.zone(for: "anycast", chosen: ["anycast": "Etc/UTC"])?.identifier == "Etc/UTC")
        #expect(PlaceZones.zone(for: "Seattle", chosen: [:])?.identifier == "America/Los_Angeles")
    }

    @Test func regionsListEveryCityZone() {
        let all = PlaceZones.regions.flatMap(\.zones)
        #expect(all.contains("America/Los_Angeles"))
        #expect(all.contains("Asia/Tokyo"))
        #expect(!all.contains { $0.hasPrefix("US/") || $0.hasPrefix("Etc/") })
        #expect(PlaceZones.city("Asia/Tokyo", locale: Locale(identifier: "ja")) == "東京")
    }
}

@Suite struct ZonesSectionTests {
    init() { L10n.force("en") }

    /// At 09:00 UTC on 1 March 2027 it is 1:00 AM in Seattle, and still the
    /// day before in Honolulu.
    @Test func groupsByZoneWestToEast() throws {
        let z = try #require(zonesPanel(.incidents).zones)
        #expect(z.zones.map(\.id) == ["Pacific/Honolulu", "America/Los_Angeles", "America/New_York", "Europe/Berlin", "Asia/Tokyo"])
        #expect(z.serverCount == 11)
        #expect(z.unplaced == 0)
        #expect(z.isCurrent)
        let pacific = z.zones[1]
        #expect(pacific.isHere)
        #expect(pacific.places == ["Seattle", "San Jose", "Los Angeles"])
        #expect(pacific.servers.count == 6)
        #expect(pacific.servers.first { $0.id == "bwh-la" }?.mark == .degraded)
        #expect(z.zones.map(\.relative) == ["−2h", "here", "+3h", "+9h", "+17h"])
        #expect(z.zones.map(\.clock) == ["11:00 PM", "1:00 AM", "4:00 AM", "10:00 AM", "6:00 PM"])
        #expect(z.zones.map(\.day) == ["yesterday", "", "", "", ""])
        #expect(z.zones.map(\.zoneName) == ["HST", "PST", "EST", "GMT+1", "GMT+9"])
        #expect(pacific.hour == 1)
    }

    /// This Mac's zone by another name is still here.
    @Test func hereByAnotherName() throws {
        let z = try #require(zonesPanel(.clear, here: "US/Pacific").zones)
        #expect(z.zones.count == 5)
        #expect(z.zones.filter(\.isHere).map(\.id) == ["America/Los_Angeles"])
    }

    /// Away from every server, This Mac gets a row of its own.
    @Test func hereWithoutServers() throws {
        let z = try #require(zonesPanel(.clear, here: "Europe/London").zones)
        #expect(z.zones.count == 6)
        let here = try #require(z.zones.first { $0.isHere })
        #expect(here.places == ["This Mac"])
        #expect(here.servers.isEmpty)
        #expect(z.zones.first { $0.id == "America/Los_Angeles" }?.relative == "−8h")
    }

    @Test func choicesMoveAndRemovePlaces() throws {
        let p = zonesPanel(.clear) { $0.sections.placeZones = ["Tokyo": "", "Seattle": "America/Tijuana"] }
        let z = try #require(p.zones)
        #expect(z.unplaced == 1)
        #expect(!z.zones.contains { $0.id == "Asia/Tokyo" })
        // Tijuana keeps Pacific time with its changes, so it is here too,
        // beside Los Angeles.
        #expect(z.zones.filter(\.isHere).map(\.id) == ["America/Tijuana", "America/Los_Angeles"])
    }

    /// Offline, the clocks go on and every mark is withheld.
    @Test func offlineWithholdsMarks() throws {
        let z = try #require(zonesPanel(.offline).zones)
        #expect(!z.isCurrent)
        #expect(z.zones.flatMap(\.servers).allSatisfy { $0.mark == .offline })
        #expect(z.zones.count == 5)
    }

    /// Without a list from `topo`, the pinned servers stand in.
    @Test func pinnedServersWithoutAList() throws {
        let z = try #require(zonesPanel(.clear, listServers: false).zones)
        #expect(z.zones.map(\.id) == ["America/Los_Angeles", "America/New_York"])
        #expect(z.serverCount == 2)
    }

    @Test func offSettingHidesIt() {
        let p = zonesPanel(.clear) { $0.sections.zones = false }
        #expect(p.zones == nil)
    }

    @Test func daylightIsAClock() {
        #expect(ZonesSection.daylight(0) == 0)
        #expect(ZonesSection.daylight(12) == 1)
        #expect(ZonesSection.daylight(6) > 0 && ZonesSection.daylight(6) < 1)
        #expect(ZonesSection.daylight(3) == 0 && ZonesSection.daylight(21) == 0)
        #expect(ZonesSection.daylight(9) == 1 && ZonesSection.daylight(15) == 1)
        #expect(abs(ZonesSection.daylight(9) - ZonesSection.daylight(15)) < 1e-9)
    }

    @Test func timesFollowTheLanguage() {
        let d = origin
        let la = TimeZone(identifier: "America/Los_Angeles")!
        L10n.with("en") { #expect(Words.time(d, in: la) == ("1:00", "AM")) }
        L10n.with("ja") { #expect(Words.time(d, in: la) == ("1:00", "")) }
        L10n.with("zh-Hans") { #expect(Words.time(d, in: la) == ("01:00", "")) }
        L10n.with("ja") { #expect(Words.offset(seconds: 3 * 3600) == "+3時間") }
        #expect(Words.offset(seconds: 19800) == "+5:30h")
        #expect(Words.offset(seconds: -36000) == "−10h")
    }
}
