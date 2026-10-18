import Foundation
import Testing
@testable import TopophanyKit

@Suite struct SettingsTests {
    /// DESIGN.md §9's example, verbatim.
    static let design = #"""
    {
      "schema": 1,
      "topo": { "path": "/opt/homebrew/bin/topo", "profile": "home", "observer": "", "interval": "5s" },
      "appearance": { "theme": "native", "panel": "system", "menuBar": { "show": "count", "statusColors": true } },
      "sections": [
        { "id": "status" },
        { "id": "seen" },
        { "id": "attention", "limit": 3 },
        { "id": "applications", "only": [] },
        { "id": "servers", "enabled": false, "nodes": ["oracle-ny", "bwh-la"] },
        { "id": "mac", "mode": "local", "readings": ["cpu", "memory", "storage", "network", "battery"], "every": "2s" }
      ],
      "openAtLogin": true,
      "terminal": "com.mitchellh.ghostty"
    }
    """#

    @Test func readsTheDesignExample() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(Self.design.utf8))
        #expect(s.topo.path == "/opt/homebrew/bin/topo")
        #expect(s.topo.profile == "home")
        #expect(s.topo.interval == "5s")
        #expect(s.appearance.theme == "native")
        #expect(s.appearance.menuBar.show == .count)
        #expect(s.sections.order == Sections.defaultOrder)
        #expect(s.sections.attentionLimit == 3)
        #expect(s.sections.servers == false)
        #expect(s.sections.serverNodes == ["oracle-ny", "bwh-la"])
        #expect(s.sections.mac.mode == .local)
        #expect(s.sections.mac.readings == Sections.Reading.allCases)
        #expect(s.terminal == "com.mitchellh.ghostty")
    }

    @Test func roundTrips() throws {
        var s = Settings()
        s.topo.observer = "seattle-macbook"
        s.sections.move(.mac, to: 1)
        s.sections.attentionLimit = 5
        s.sections.mac.mode = .server
        s.sections.mac.node = "macbook"
        s.appearance.theme = "terminal"
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(back.sections.order.first == .status)
        #expect(back.sections.order[1] == .mac)
    }

    @Test func missingAndUnknownFields() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"future":1,"topo":{"interval":"90m"},"sections":[{"id":"mac","mode":"off"},{"id":"bogus"},{"id":"status"}]}"#.utf8))
        #expect(s.topo.interval == "1h")
        #expect(s.sections.order == [.status, .mac, .seen, .attention, .applications, .servers])
        #expect(s.sections.mac.mode == .off)
        #expect(s.sections.isEnabled(.mac) == false)
        #expect(s.appearance == Settings.Appearance())
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
    }
}
