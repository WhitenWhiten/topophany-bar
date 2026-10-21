import Foundation
import Testing
@testable import TopophanyKit

/// `map.graph` (PROTOCOL.md §3), the map's settings, and when the request
/// asks for it.
@Suite struct MapGraphTests {
    static let row = #"""
    {"schema":1,"name":"stream","request_id":"r","config_revision":"c","instance":"i","sequence":1,"source":"client",
     "lifecycle":"running","generated_at":"2026-10-18T13:30:00Z","publisher_expires_at":"2026-10-18T13:30:30Z","rows":[
     {"id":"map","metric":"map.graph","visual":"map","value":{
       "nodes":[
         {"id":"oracle-ny","name":"Oracle New York","kind":"host","provider":"Oracle","place":"New York","lat":40.71,"lon":-74.01,
          "located":true,"health":"up","signal":"up"},
         {"id":"bwh-la","name":"","kind":"host","place":"Los Angeles","lat":34.05,"lon":-118.24,"health":"degraded",
          "affected":true,"signal":"affected"},
         {"id":"vercel","name":"Vercel","kind":"edge","place":"","lat":null,"lon":null,"located":false,"health":"up"},
         {"id":"guessed","name":"Guessed","place":"Lisbon","lat":38.7,"lon":-9.1,"located":false,"health":"up"},
         {"id":"far","name":"Far","place":"?","lat":95,"lon":10,"health":"up"},
         {"id":"new","name":"New","lat":1,"lon":2,"health":"up","signal":"glowing"}],
       "edges":[
         {"id":"e1","from":"oracle-ny","to":"bwh-la","kind":"link","signal":"degraded"},
         {"from":"bwh-la","to":"vercel","kind":"path","signal":"down","observer":"san-jose"},
         {"from":"bwh-la","to":"nowhere","kind":"link","signal":"up"},
         {"from":"oracle-ny","to":"new","kind":"tunnel","signal":"up"}]},
      "text":"6 nodes in 4 places","health":"degraded","freshness":"fresh","valid_until":"2026-10-18T13:30:20Z"}]}
    """#

    @Test func decodesTheGraph() throws {
        let f = try JSONDecoder().decode(Frame.self, from: Data(Self.row.utf8))
        guard case .map(let g) = f.rows.first?.value else {
            Issue.record("not a map: \(String(describing: f.rows.first?.value))")
            return
        }
        #expect(g.nodes.map(\.id) == ["oracle-ny", "bwh-la", "vercel", "guessed", "far", "new"])
        let ny = g.nodes[0]
        #expect(ny.located && ny.lat == 40.71 && ny.lon == -74.01)
        #expect(ny.signal == .up)
        // A missing name is the ID; a missing signal follows health.
        #expect(g.nodes[1].name == "bwh-la")
        #expect(g.nodes[1].signal == .affected)
        #expect(g.nodes[2].signal == .up)
        // Placed only where topo says so and both numbers are in range.
        #expect(!g.nodes[2].located && g.nodes[2].lat == nil)
        #expect(!g.nodes[3].located && g.nodes[3].lat == nil, "located false keeps it off the map")
        #expect(!g.nodes[4].located, "a latitude past the pole")
        #expect(g.nodes[5].signal == .other("glowing"))
        // An edge needs both its ends.
        #expect(g.edges.map(\.id) == ["e1", "bwh-la→vercel", "oracle-ny→new"])
        #expect(g.edges[0].signal == .degraded)
        #expect(g.edges[1].kind == .path && g.edges[1].observer == "san-jose")
        #expect(g.edges[2].kind == .other("tunnel"))
    }

    @Test func capabilities() throws {
        let with = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"metrics":[{"name":"map.graph","visual":"map"}]}"#.utf8))
        #expect(with.drawsMap)
        let without = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"metrics":[{"name":"servers.list"}]}"#.utf8))
        #expect(!without.drawsMap)
    }

    @Test func settingsRoundTrip() throws {
        var s = Settings()
        #expect(s.sections.map && s.sections.mapFrame == .fit)
        s.sections.mapFrame = .world
        s.sections.map = false
        let data = try JSONEncoder().encode(s)
        #expect(String(decoding: data, as: UTF8.self).contains(#""frame":"world""#))
        let back = try JSONDecoder().decode(Settings.self, from: data)
        #expect(back == s)
        // A word this app doesn't know is the default.
        let odd = try JSONDecoder().decode(Settings.self, from: Data(#"{"sections":[{"id":"map","mode":"flat","frame":"globe"}]}"#.utf8))
        #expect(odd.sections.mapFrame == .fit && odd.sections.map)
    }

    @Test func legacyMapModeIsIgnored() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"sections":[{"id":"map","mode":"virtual","frame":"world","enabled":false},{"id":"mac","mode":"server","node":"macbook"}]}"#.utf8))
        #expect(settings.sections.mapFrame == .world && !settings.sections.map)
        #expect(settings.sections.mac.mode == .server && settings.sections.mac.node == "macbook")
        let data = try JSONEncoder().encode(settings)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sections = try #require(object["sections"] as? [[String: Any]])
        let map = try #require(sections.first { ($0["id"] as? String) == "map" })
        #expect(map["mode"] == nil)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
    }

    /// The row is asked for only of a topo that draws the map, while the
    /// panel or a Map widget shows it.
    @Test func requestsTheGraph() {
        func asks(_ s: Settings, widgets: TemplateCompiler.WidgetNeeds = .none, mapGraph: Bool) -> Bool {
            TemplateCompiler().request(for: s, revision: 1, widgets: widgets, mapGraph: mapGraph).template.rows
                .contains { $0.id == TemplateCompiler.RowID.map && $0.metric == "map.graph" }
        }
        var s = Settings()
        #expect(asks(s, mapGraph: true))
        #expect(!asks(s, mapGraph: false))
        s.sections.map = false
        #expect(!asks(s, mapGraph: true))
        #expect(asks(s, widgets: .init(map: true), mapGraph: true))
        #expect(!asks(s, widgets: .init(map: true), mapGraph: false))
        // Its framing is the app's: the request doesn't change.
        var t = Settings()
        t.sections.mapFrame = .world
        #expect(TemplateCompiler().request(for: t, revision: 1, mapGraph: true) == TemplateCompiler().request(for: Settings(), revision: 1, mapGraph: true))
    }
}
