import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

/// Servers read from a source: how their readings stand where `topo`
/// judges no health for them, and how sources are named.
struct SourceReadingTests {
    static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures")
    static let now = Timestamp.parse("2026-10-21T12:00:00Z")!

    func reading(_ path: String, at: Date = now) throws -> Reading {
        let data = try Data(contentsOf: Self.fixtures.appending(path: path))
        let frame = try #require(FrameDecoder.frame(from: data))
        var policy = ReaderPolicy(); policy.receive(frame, line: data, at: Self.now)
        return policy.evaluate(at: at)
    }

    func panel(_ path: String, source: String, at: Date = now) throws -> PanelModel {
        let r = try reading(path, at: at)
        var s = Settings(); s.topo.source = source; s.sections.servers = true; s.sections.fleet = true; s.sections.mac.mode = .off
        s.sections.serverNodes = r.rows.compactMap(\.row.select?.node)
        return SectionBuilder.panel(.init(reading: r, engine: .running, settings: s))
    }

    @Test func directServersSayHowTheyAreRead() throws {
        let p = try panel("DirectDevelopment/fleet_partial.json", source: "direct")
        let byName = Dictionary(uniqueKeysWithValues: p.servers.map { ($0.name, $0) })
        let nas = try #require(byName["nas"])
        #expect(nas.samples == .current && nas.mark == .up && nas.pill.text == "CURRENT")
        #expect(nas.showsSizes && nas.memory.detail == "8.4 / 16 GiB")
        let stale = try #require(byName["pi-hole"])
        #expect(stale.samples == .stale && stale.mark == .offline && stale.pill.text == "STALE")
        #expect(stale.age.hasPrefix("last reading"))
        let missing = try #require(byName["build-01"])
        #expect(missing.samples == .missing && missing.mark == .offline && missing.pill.text == "NO SAMPLES")
        // Fleet takes each listed server's mark from its card.
        let fleet = try #require(p.fleet).groups.flatMap(\.nodes)
        #expect(fleet.map(\.mark) == [.up, .up, .offline, .offline])
    }

    @Test func contractStatesMapToSamples() throws {
        let expected: [String: (ServerCardModel.Samples, Mark)] = [
            "stream-ready": (.current, .up), "stream-expired": (.stale, .offline), "stream-no-data": (.missing, .offline),
        ]
        let root = Self.fixtures.deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/contracts/direct-v1/fixtures")
        for (name, (samples, mark)) in expected {
            let data = try Data(contentsOf: root.appending(path: name + ".json"))
            let frame = try #require(FrameDecoder.frame(from: data))
            let at = try #require(frame.generatedAt)
            var policy = ReaderPolicy(); policy.receive(frame, line: data, at: at)
            var s = Settings(); s.topo.source = "direct"; s.sections.servers = true
            s.sections.serverNodes = frame.rows.compactMap(\.select?.node)
            let card = try #require(SectionBuilder.panel(.init(reading: policy.evaluate(at: at), engine: .running, settings: s)).servers.first)
            #expect(card.samples == samples, "\(name)")
            #expect(card.mark == mark, "\(name)")
        }
    }

    @Test func collectorKeepsItsJudgmentAndNamesKomari() throws {
        let p = try panel("CollectorSources/komari.json", source: "client")
        let byName = Dictionary(uniqueKeysWithValues: p.servers.map { ($0.name, $0) })
        let hk = try #require(byName["hk-1"])
        #expect(hk.samples == nil && hk.pill.text == "UP" && !hk.showsSizes)
        #expect(hk.origin?.badge == "Komari" && hk.subtitle == "host · Vultr · Hong Kong")
        #expect(byName["tokyo-2"]?.pill.text == "WARN")
        let fra = try #require(byName["fra-3"])
        #expect(fra.samples == .stale && fra.subtitle == "host · Komari Monitor · Frankfurt")
        #expect(byName["nas"]?.subtitle == "host · Home Beszel")
        let listed = ListedSource.from(try reading("CollectorSources/komari.json"))
        #expect(listed.map(\.name) == ["Komari Monitor", "Home Beszel"])
        #expect(listed.first?.servers == ["hk-1", "tokyo-2", "fra-3"])
    }

    @Test func adaptersAreNamed() throws {
        func origin(_ adapter: String, _ name: String) -> Origin {
            try! JSONDecoder().decode(Origin.self, from: Data(#"{"adapter":"\#(adapter)","source_id":"s","name":"\#(name)","object_id":"o"}"#.utf8))
        }
        #expect(origin("komari", "Komari Monitor").detail == "Komari Monitor")
        #expect(origin("komari", "Edge").detail == "Komari · Edge")
        #expect(origin("beszel", "Home Beszel").detail == "Home Beszel")
        #expect(origin("netdata", "Lab").badge == "Source")
        func status(_ adapters: [String]) throws -> SourceStatusSection {
            let sources = adapters.enumerated().map { #"{"id":"s\#($0.offset)","name":"n","adapter":"\#($0.element)","state":"connected"}"# }
            let json = #"{"state":"ready","sources":[\#(sources.joined(separator: ","))]}"#
            return SourceStatusSection(value: try JSONDecoder().decode(SourcesStatus.self, from: Data(json.utf8)), isCurrent: true)
        }
        #expect(try status(["beszel", "beszel"]).adapter == "Beszel")
        #expect(try status(["komari"]).adapter == "Komari")
        #expect(try status(["beszel", "komari"]).adapter == "Direct")
        #expect(try status([]).adapter == "Direct")
    }
}
