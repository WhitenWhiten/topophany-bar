import Foundation
import Testing
@testable import TopophanySections
import TopophanyEngine
import TopophanyKit

/// The Map section: `topo`'s graph as it sent it, withheld when it's old,
/// and without it the places `servers.list` names.
@Suite struct MapSectionTests {
    init() { L10n.force("en") }

    func map(_ scenario: FixtureEngine.Scenario, after: TimeInterval = 4, observer: String = "", mapGraph: Bool = true,
             listServers: Bool = true, settings s: Settings = settings()) -> MapSection? {
        var s = s
        s.topo.observer = observer
        let request = TemplateCompiler().request(for: s, revision: 1, listServers: listServers, mapGraph: mapGraph)
        let reading = FixtureEngine.reading(scenario, request: request, origin: origin, after: after)
        return SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: s)).map
    }

    @Test func drawsTheGraph() throws {
        let m = try #require(map(.incidents))
        #expect(m.source == .graph && m.isCurrent)
        #expect(m.mode == .geo && m.frame == .fit)
        // Every place topo names, colos aside, in its order.
        #expect(m.places == ["Seattle", "San Jose", "Los Angeles", "Honolulu", "New York", "Tokyo", "Frankfurt"])
        let byID = Dictionary(uniqueKeysWithValues: m.nodes.map { ($0.id, $0) })
        // Marks are topo's signals: affected and degraded a triangle.
        #expect(byID["bwh-la"]?.mark == .degraded)
        #expect(byID["oracle-la"]?.mark == .degraded)
        #expect(byID["oracle-ny"]?.mark == .up)
        // A container inherits its host's place; an edge has none.
        #expect(byID["postgres-box"]?.coordinate == byID["oracle-ny"]?.coordinate)
        #expect(byID["cloudflare"]?.coordinate == nil)
        #expect(m.unplaced.contains { $0.id == "cloudflare" })
        // A colo is evidence of a route, drawn as such.
        #expect(byID["colo:cloudflare:SJC"]?.isColo == true)
        #expect(!m.places.contains("SJC"))
        // Containment isn't a line.
        #expect(!m.edges.contains { $0.id.hasPrefix("parent:") })
        let e = Dictionary(uniqueKeysWithValues: m.edges.map { ($0.id, $0) })
        #expect(e["win-transit"]?.line == .down)
        #expect(e["transit-exit-a"]?.line == .affected)
        #expect(e["exit-a-net"]?.line == .affected)
        #expect(e["cf-app"]?.line == .up)
        #expect(e["visitors-cf"]?.line == .carried)
    }

    /// A hop a declared path implies shows when it needs a look, or when
    /// it's the viewing observer's own path; a passing one otherwise not.
    @Test func pathHops() throws {
        #expect(try #require(map(.incidents)).edges.contains { $0.id == "path:relay-entry" && $0.line == .down })
        #expect(try #require(map(.clear)).edges.contains { $0.id == "path:relay-entry" } == false)
        let own = try #require(map(.clear, observer: "san-jose"))
        #expect(own.edges.first { $0.id == "path:relay-entry" }?.line == .carried)
        #expect(try #require(map(.clear, observer: "frankfurt")).edges.contains { $0.id == "path:relay-entry" } == false)
    }

    /// Once the row lapses, where things are stays as history: every mark
    /// withheld, every line with them, the paths gone.
    @Test func withheldWhenOld() throws {
        let m = try #require(map(.stale, after: 60))
        #expect(!m.isCurrent)
        #expect(m.nodes.allSatisfy { $0.mark == .offline })
        #expect(m.edges.allSatisfy { $0.line == .withheld })
        #expect(!m.edges.contains { $0.kind == .path })
        #expect(!m.places.isEmpty)
    }

    /// Without `map.graph`, servers.list's places where their names say,
    /// marked as topo marked each server, with no lines.
    @Test func placesByNameWithoutTheGraph() throws {
        let m = try #require(map(.incidents, mapGraph: false))
        #expect(m.source == .places)
        #expect(m.edges.isEmpty)
        let byID = Dictionary(uniqueKeysWithValues: m.nodes.map { ($0.id, $0) })
        #expect(byID["bwh-la"]?.mark == .degraded)
        let la = try #require(byID["bwh-la"]?.coordinate)
        #expect(abs(la.lat - 34.05) < 0.01 && abs(la.lon + 118.24) < 0.01)
        // Without the list, the pinned servers' cards.
        let pinned = try #require(map(.incidents, mapGraph: false, listServers: false))
        #expect(Set(pinned.nodes.map(\.id)) == ["oracle-ny", "bwh-la"])
        // And with neither, no map.
        var none = settings(servers: false)
        none.sections.serverNodes = []
        #expect(map(.incidents, mapGraph: false, listServers: false, settings: none) == nil)
    }

    @Test func modeAndFrameFromSettings() throws {
        var s = settings()
        s.sections.mapMode = .virtual
        s.sections.mapFrame = .world
        let m = try #require(map(.clear, settings: s))
        #expect(m.mode == .virtual && m.frame == .world)
        s.sections.map = false
        #expect(map(.clear, settings: s) == nil)
    }

    /// topo's gazetteer in each language it spells, then the city a time
    /// zone is named for; nothing for a name that's no city.
    @Test func placesByName() throws {
        let tokyo = try #require(MapPlaces.coordinate(for: "Tokyo"))
        #expect(MapPlaces.coordinate(for: "東京") == tokyo)
        #expect(MapPlaces.coordinate(for: "东京") == tokyo)
        #expect(MapPlaces.coordinate(for: "tokyo") == tokyo)
        // Not in the gazetteer, but a time zone's city.
        let lisbon = try #require(MapPlaces.coordinate(for: "Lisbon"))
        #expect(abs(lisbon.lat - 38.7) < 0.2 && abs(lisbon.lon + 9.1) < 0.3)
        #expect(MapPlaces.coordinate(for: "anycast") == nil)
        #expect(MapPlaces.coordinate(for: "") == nil)
        // ISO 6709, as zone.tab writes it: ±DDMM±DDDMM or with seconds.
        #expect(MapPlaces.iso6709("+3443-11815") == MapSection.Coordinate(lat: 34 + 43.0 / 60, lon: -(118 + 15.0 / 60)))
        let s = try #require(MapPlaces.iso6709("-332552+1511220"))
        #expect(abs(s.lat + (33 + 25.0 / 60 + 52.0 / 3600)) < 1e-9 && abs(s.lon - (151 + 12.0 / 60 + 20.0 / 3600)) < 1e-9)
        #expect(MapPlaces.iso6709("garbage") == nil)
    }
}
