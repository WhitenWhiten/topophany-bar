import Foundation
import Testing
@testable import TopophanyKit

@Suite struct SettingsTests {
    @Test func whiteNightIconPersists() throws {
        var settings = Settings()
        settings.appearance.menuBar.icon = .whiteNight
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(back.appearance.menuBar.icon == .whiteNight)
    }
    @Test func mapLockDefaultsOnForExistingSettings() throws {
        #expect(Settings().sections.mapLocked)
        for json in ["{}", #"{"sections":[{"id":"map","enabled":true,"frame":"world"}]}"#] {
            let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
            #expect(settings.sections.mapLocked)
        }
    }

    @Test func mapLockPersistsWithoutChangingTheMonitorRequest() throws {
        for locked in [false, true] {
            var settings = Settings()
            settings.sections.mapLocked = locked
            settings.sections.mapFrame = .world
            let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
            #expect(back == settings)
            #expect(back.sections.mapLocked == locked)
            var other = settings
            other.sections.mapLocked.toggle()
            #expect(TemplateCompiler().request(for: settings, revision: 1) == TemplateCompiler().request(for: other, revision: 1))
        }
    }

    @Test func panelShortcutPersistsAndDoesNotChangeTheMonitorRequest() throws {
        var settings = Settings()
        #expect(settings.panelShortcut == nil)
        settings.panelShortcut = PanelShortcut(keyCode: 49, modifiers: [.control, .option])
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(back == settings)
        #expect(TemplateCompiler().request(for: settings, revision: 1) == TemplateCompiler().request(for: Settings(), revision: 1))
    }

    @Test func invalidSavedShortcutsAreDisabled() throws {
        for json in ["null", "{}", #"{"keyCode":49,"modifiers":0}"#,
                     #"{"keyCode":55,"modifiers":8}"#,
                     #"{"keyCode":500,"modifiers":8}"#,
                     #"{"keyCode":49,"modifiers":16}"#,
                     #"{"keyCode":-1,"modifiers":8}"#,
                     #"{"keyCode":49,"modifiers":"command"}"#] {
            let settings = try JSONDecoder().decode(Settings.self, from: Data("{\"panelShortcut\":\(json)}".utf8))
            #expect(settings.panelShortcut == nil)
        }
        #expect(!PanelShortcut(keyCode: 0, modifiers: .shift).isValid)
        #expect(PanelShortcut(keyCode: 0, modifiers: [.control, .shift]).isValid)
    }

    /// DESIGN.md §9's example, verbatim.
    static let design = #"""
    {
      "schema": 1,
      "topo": { "path": "/opt/homebrew/bin/topo", "profile": "home", "observer": "", "interval": "5s" },
      "appearance": { "theme": "native", "panel": "system",
                      "menuBar": { "show": "count", "statusColors": true, "motion": true, "readings": [] } },
      "sections": [
        { "id": "status" },
        { "id": "seen" },
        { "id": "attention", "limit": 3 },
        { "id": "applications", "only": [] },
        { "id": "fleet", "enabled": true },
        { "id": "servers", "enabled": false, "nodes": ["oracle-ny", "bwh-la"] },
        { "id": "zones", "enabled": true, "places": { "Seattle": "America/Los_Angeles" } },
        { "id": "mac", "mode": "local", "readings": ["cpu", "memory", "storage", "network", "battery"], "every": "2s" }
      ],
      "openAtLogin": true,
      "terminal": "com.mitchellh.ghostty",
      "language": "system"
    }
    """#

    @Test func readsTheDesignExample() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(Self.design.utf8))
        #expect(s.topo.path == "/opt/homebrew/bin/topo")
        #expect(s.topo.profile == "home")
        #expect(s.topo.interval == "5s")
        #expect(s.appearance.theme == "native")
        #expect(s.appearance.menuBar.show == .count)
        #expect(s.appearance.menuBar.motion)
        #expect(s.appearance.menuBar.readings.isEmpty)
        #expect(s.sections.order == Sections.defaultOrder)
        #expect(s.sections.attentionLimit == 3)
        #expect(s.sections.servers == false)
        #expect(s.sections.serverNodes == ["oracle-ny", "bwh-la"])
        #expect(s.sections.zones)
        #expect(s.sections.placeZones == ["Seattle": "America/Los_Angeles"])
        #expect(s.sections.mac.mode == .local)
        #expect(s.sections.mac.readings == Sections.Reading.allCases)
        #expect(s.terminal == "com.mitchellh.ghostty")
        #expect(s.language == .system)
    }

    /// Motion is on unless turned off; readings keep their own order, and
    /// one this app doesn't know is dropped.
    @Test func menuBarReadings() throws {
        func menuBar(_ json: String) throws -> Settings.Appearance.MenuBar {
            try JSONDecoder().decode(Settings.self, from: Data(#"{"appearance": {"menuBar": \#(json)}}"#.utf8)).appearance.menuBar
        }
        #expect(try menuBar("{}") == Settings.Appearance.MenuBar())
        #expect(try menuBar("{}").motion)
        #expect(try menuBar("{}").icon == .globe)
        #expect(try menuBar(#"{"icon": "deepseek"}"#).icon == .deepseek)
        #expect(try menuBar(#"{"icon": "future-icon"}"#).icon == .globe)
        #expect(try menuBar(#"{"icon": "custom", "customIconID": "../other"}"#).icon == .globe)
        #expect(try menuBar(#"{"iconSize": 100, "iconSpeed": -1}"#).iconSize == 26)
        #expect(try menuBar(#"{"iconSize": 100, "iconSpeed": -1}"#).iconSpeed == 1)
        let custom = try menuBar(#"{"icon":"custom","customIconID":"01010101-0000-0000-0000-000000000001","iconSize":22,"iconSpeed":1.5}"#)
        #expect(custom.icon == .custom)
        #expect(try JSONDecoder().decode(Settings.Appearance.MenuBar.self, from: JSONEncoder().encode(custom)) == custom)
        let portrait = try menuBar(#"{"icon": "deepseek"}"#)
        #expect(try JSONDecoder().decode(Settings.Appearance.MenuBar.self, from: JSONEncoder().encode(portrait)).icon == .deepseek)
        #expect(try menuBar(#"{"motion": false}"#).motion == false)
        #expect(try menuBar(#"{"readings": ["network", "gpu", "cpu", "cpu"]}"#).readings == [.cpu, .network])
        #expect(try menuBar(#"{"readings": "cpu"}"#).readings.isEmpty)
        var m = Settings.Appearance.MenuBar()
        m.setReading(.network, true)
        m.setReading(.cpu, true)
        #expect(m.readings == [.cpu, .network])
        m.setReading(.network, false)
        #expect(m.readings == [.cpu])
    }

    /// The panel's height, as its foot was left: absent, or anything but a
    /// positive whole number, is as tall as the screen allows. It's how
    /// the panel looks, so `topo` never hears of it.
    @Test func panelHeight() throws {
        func height(_ json: String) throws -> Int? {
            try JSONDecoder().decode(Settings.self, from: Data(#"{"appearance": \#(json)}"#.utf8)).appearance.panelHeight
        }
        #expect(try height("{}") == nil)
        #expect(try height(#"{"panelHeight": 640}"#) == 640)
        #expect(try height(#"{"panelHeight": 0}"#) == nil)
        #expect(try height(#"{"panelHeight": -20}"#) == nil)
        #expect(try height(#"{"panelHeight": "tall"}"#) == nil)
        var s = Settings()
        #expect(!String(decoding: try JSONEncoder().encode(s), as: UTF8.self).contains("panelHeight"))
        s.appearance.panelHeight = 600
        #expect(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s)) == s)
        #expect(TemplateCompiler().request(for: s, revision: 1) == TemplateCompiler().request(for: Settings(), revision: 1))
    }

    @Test func roundTrips() throws {
        var s = Settings()
        s.topo.observer = "seattle-macbook"
        s.sections.move(.mac, to: 1)
        s.sections.attentionLimit = 5
        s.sections.mac.mode = .server
        s.sections.mac.node = "macbook"
        s.appearance.theme = "terminal"
        s.appearance.menuBar.motion = false
        s.appearance.menuBar.readings = [.memory, .network]
        s.language = .zhHans
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(back.sections.order.first == .status)
        #expect(back.sections.order[1] == .mac)
    }

    @Test func missingAndUnknownFields() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"future":1,"topo":{"interval":"90m"},"sections":[{"id":"mac","mode":"off"},{"id":"bogus"},{"id":"status"}]}"#.utf8))
        #expect(s.topo.interval == "1h")
        #expect(s.sections.order == [.status, .seen, .attention, .map, .applications, .services, .fleet, .servers, .zones, .mac])
        #expect(s.sections.mac.mode == .off)
        #expect(s.sections.isEnabled(.mac) == false)
        #expect(s.appearance == Settings.Appearance())
        #expect(s.language == .system)
    }

    /// The languages Topophany is translated into; any other follows the
    /// system.
    @Test func language() throws {
        func decode(_ json: String) throws -> Settings.Language {
            try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).language
        }
        #expect(try decode(#"{"language":"ja"}"#) == .ja)
        #expect(try decode(#"{"language":"zh-Hans"}"#) == .zhHans)
        #expect(try decode(#"{"language":"fr"}"#) == .system)
        #expect(try decode(#"{"language":7}"#) == .system)
        #expect(Settings.Language.system.localization == nil)
        #expect(Settings.Language.zhHans.localization == "zh-Hans")
    }

    /// A file that lacks a section, as one from before it existed would,
    /// gets it after the section that precedes it by default, and keeps
    /// its own order.
    @Test func missingSectionsTakeTheirPlace() throws {
        let old = #"{"sections":[{"id":"status"},{"id":"mac"},{"id":"seen"},{"id":"attention"},{"id":"servers"}]}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(old.utf8))
        #expect(s.sections.order == [.status, .mac, .seen, .attention, .map, .applications, .services, .fleet, .servers, .zones])
        // Time zones, Fleet and Map, newer than such a file, are on, the map
        // as the TUI frames it.
        #expect(s.sections.zones)
        #expect(s.sections.map)
        #expect(s.sections.mapFrame == .fit)
        #expect(s.sections.fleet)
        #expect(s.sections.placeZones.isEmpty)
        // Services, newer still, are off until pinned.
        #expect(!s.sections.services)
        #expect(s.sections.serviceIDs.isEmpty)
    }

    /// Pinned services by ID, in the order they were pinned; off by default.
    @Test func servicesRoundTrip() throws {
        #expect(!Settings().sections.services)
        #expect(!Settings().sections.isEnabled(.services))
        var s = Settings()
        s.sections.setEnabled(.services, true)
        s.sections.serviceIDs = ["vless-entry", "main-site"]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        #expect(back == s)
        #expect(back.sections.isEnabled(.services))
        #expect(String(decoding: data, as: UTF8.self).contains(#""ids":["vless-entry","main-site"]"#))
    }

    @Test func zonesRoundTrip() throws {
        var s = Settings()
        s.sections.zones = false
        s.sections.placeZones = ["Seattle": "America/Vancouver", "anycast": ""]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        #expect(back == s)
        #expect(String(decoding: data, as: UTF8.self).contains(#""id":"zones""#))
    }

    @Test func statusCantMove() {
        var s = Sections()
        s.move(.status, to: 3)
        s.move(.servers, to: 0)
        #expect(s.order.first == .status)
        #expect(s.order[1] == .servers)
    }

    @Test func storeKeepsAnUnreadableFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = SettingsStore(url: dir.appending(path: "settings.json"))
        #expect(store.load() == Settings())
        var s = Settings()
        s.topo.profile = "home"
        try store.save(s)
        #expect(store.load() == s)
        try Data("{oops".utf8).write(to: store.url)
        #expect(store.load() == Settings())
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "settings.unreadable.json").path))
    }
}

@Suite struct TemplateCompilerTests {
    func json(_ r: Request) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: try r.line()) as! [String: Any]
    }

    @Test func compilesTheDefaults() throws {
        let r = TemplateCompiler().request(for: Settings(), revision: 7)
        #expect(r.requestID == "settings-7")
        #expect(r.source == "client")
        #expect(r.scenario == nil)
        #expect(r.template.bar.row == "status")
        #expect(r.template.rows.map(\.id) == ["status", "seen", "attention", "apps"])
        #expect(r.template.rows.map(\.visual) == ["status", "list", "list", "list"])
        #expect(r.template.rows[2].limit == 3)
        let line = try r.line()
        #expect(line.last == 0x0A)
        #expect(!line.dropLast().contains(0x0A))
        let j = try json(r)
        #expect(j["schema"] as? Int == 1)
        #expect(j["scenario"] == nil)
        #expect(j["interval"] as? String == "5s")
    }

    @Test func followsSectionOrderAndChoices() throws {
        var s = Settings()
        s.sections.servers = true
        s.sections.serverNodes = ["oracle-ny", "bwh-la", "oracle-ny", "not valid!"]
        s.sections.mac.mode = .server
        s.sections.mac.node = "macbook"
        s.sections.attentionLimit = 5
        s.sections.seen = false
        s.sections.move(.mac, to: 1)
        let r = TemplateCompiler().request(for: s, revision: 1)
        #expect(r.template.rows.map(\.id) == ["status", "mac", "attention", "apps", "server-1", "server-2"])
        #expect(r.template.rows[1].select?.node == "macbook")
        #expect(r.template.rows[1].metric == "server.card")
        #expect(r.template.rows[1].visual == "card")
        #expect(r.template.rows[2].limit == 5)
        #expect(r.template.rows[5].select?.node == "bwh-la")
    }

    @Test func addsWhatWidgetsNeed() {
        var s = Settings()
        s.sections.seen = false
        s.sections.attention = false
        s.sections.servers = false
        s.sections.serverNodes = ["oracle-ny"]
        let r = TemplateCompiler().request(for: s, revision: 1, widgets: .init(lists: true, nodes: ["oracle-ny", "macbook"]))
        #expect(r.template.rows.map(\.id) == ["status", "seen", "attention", "apps", "server-1", "widget-server-1"])
        #expect(r.template.rows[2].limit == 3)
        #expect(r.template.rows[5].select?.node == "macbook")
    }

    /// Pinned services' cards, and a Service widget's, only from a `topo`
    /// that offers `service.card`: an older one would refuse the request.
    @Test func pinsServicesOnlyWhenTopoCardsThem() {
        var s = Settings()
        s.sections.seen = false
        s.sections.attention = false
        s.sections.applications = false
        s.sections.services = true
        s.sections.serviceIDs = ["vless-entry", "main-site", "vless-entry", "not valid!"]
        let widgets = TemplateCompiler.WidgetNeeds(services: ["main-site", "workers-api"])
        let old = TemplateCompiler().request(for: s, revision: 1, widgets: widgets)
        #expect(old.template.rows.map(\.id) == ["status"])
        let r = TemplateCompiler().request(for: s, revision: 1, widgets: widgets, serviceCards: true, listServices: true)
        #expect(r.template.rows.map(\.id) == ["status", "service-1", "service-2", "widget-service-1", "services"])
        #expect(r.template.rows[1].metric == "service.card")
        #expect(r.template.rows[1].visual == "card")
        #expect(r.template.rows[1].select == .init(service: "vless-entry"))
        #expect(r.template.rows[3].select?.service == "workers-api")
        #expect(r.template.rows[4].metric == "services.list")
        // Off, nothing is asked for the panel.
        s.sections.services = false
        #expect(TemplateCompiler().request(for: s, revision: 1, serviceCards: true).template.rows.map(\.id) == ["status"])
    }

    @Test func listsServersOnlyWhenAsked() {
        let s = Settings()
        #expect(!TemplateCompiler().request(for: s, revision: 1).template.rows.contains { $0.metric == "servers.list" })
        let r = TemplateCompiler().request(for: s, revision: 1, listServers: true)
        let row = r.template.rows.last
        #expect(row?.id == "servers")
        #expect(row?.metric == "servers.list")
        #expect(row?.visual == "list")
    }

    @Test func previewSource() {
        var s = Settings()
        s.topo.source = "preview"
        s.topo.scenario = 3
        s.topo.profile = "home"
        s.topo.interval = "0.2s"
        let r = TemplateCompiler().request(for: s, revision: 1, lang: "ja")
        #expect(r.source == "preview")
        #expect(r.scenario == 3)
        #expect(r.lang == "ja")
        #expect(r.profile == "")
        #expect(r.interval == "1s")
    }

    @Test func nodeIDs() {
        #expect(TemplateCompiler.validNode("oracle-ny"))
        #expect(TemplateCompiler.validNode("a.b_c-9"))
        #expect(!TemplateCompiler.validNode("-x"))
        #expect(!TemplateCompiler.validNode(""))
        #expect(!TemplateCompiler.validNode("é"))
        #expect(!TemplateCompiler.validNode(String(repeating: "a", count: 97)))
    }
}

@Suite struct IntervalTests {
    @Test func parsesAndFormats() {
        #expect(Interval("5s")?.seconds == 5)
        #expect(Interval("1m30s")?.seconds == 90)
        #expect(Interval("1h")?.seconds == 3600)
        #expect(Interval("250ms")?.seconds == 0.25)
        #expect(Interval("1.5s")?.seconds == 1.5)
        #expect(Interval("") == nil)
        #expect(Interval("5") == nil)
        #expect(Interval("5x") == nil)
        #expect(Interval(seconds: 90).description == "1m30s")
        #expect(Interval(seconds: 3600).description == "1h")
        #expect(Interval(seconds: 5).description == "5s")
        #expect(Interval(seconds: 7200).clampedToRefresh.description == "1h")
    }
}

@Suite struct CapabilitiesTests {
    @Test func decodes() throws {
        let line = #"{"protocol":1,"version":"1.3.0","sources":["client","preview"],"visuals":["text","bar","status","list","card"],"metrics":[{"name":"summary.verdict","type":"object","sources":["client","collector"],"visual":"status"},{"name":"observers.verdicts","visual":"list"},{"name":"attention.list"},{"name":"applications.list"},{"name":"server.card"}]}"#
        let c = try JSONDecoder().decode(Capabilities.self, from: Data(line.utf8))
        #expect(c.version == "1.3.0")
        #expect(c.isUsable)
        let old = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":2,"metrics":[{"name":"summary.verdict"}]}"#.utf8))
        #expect(!old.isUsable)
        #expect(old.missing() == ["observers.verdicts", "attention.list", "applications.list", "server.card"])
        let both = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":2,"protocols":[1,2],"metrics":[{"name":"summary.verdict"},{"name":"observers.verdicts"},{"name":"attention.list"},{"name":"applications.list"},{"name":"server.card"}]}"#.utf8))
        #expect(both.isUsable)
        #expect(!c.profiles)
        #expect(!c.listsServers)
        let more = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"metrics":[{"name":"servers.list","visual":"list"}],"profiles":true}"#.utf8))
        #expect(more.profiles)
        #expect(more.listsServers)
        #expect(!more.cardsServices && !more.listsServices)
        let services = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"metrics":[{"name":"service.card","visual":"card"},{"name":"services.list","visual":"list"}]}"#.utf8))
        #expect(services.cardsServices && services.listsServices)
        // Neither is required: a topo without them draws everything else.
        #expect(!Capabilities.required.contains("service.card"))
    }

    @Test func profiles() throws {
        let line = #"{"profiles":[{"name":"home","project":"homelab","active":true},{"name":"work","project":"","active":false}]}"#
        let p = try JSONDecoder().decode(ProfileList.self, from: Data(line.utf8))
        #expect(p.profiles.map(\.name) == ["home", "work"])
        #expect(p.active?.name == "home")
        #expect(p.profiles[1].project == "")
        let none = try JSONDecoder().decode(ProfileList.self, from: Data(#"{"profiles":[]}"#.utf8))
        #expect(none.profiles.isEmpty)
        #expect(none.active == nil)
    }
}
