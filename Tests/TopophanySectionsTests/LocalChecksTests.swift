import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

/// This Mac's proxy engine, from its own stream, beside the panel's source.
@Suite struct LocalChecksTests {
    typealias F = MonitorFixtures

    func local() throws -> LocalChecksInput {
        let engine = F.check("lc-a", kind: "mihomo", diagnostic: [
            "outcome": "ok", "evidence": "reported", "stage": "adapter", "policy": "matched",
            "facts": ["mode": "rule", "tun_enabled": "false"], "expected": ["mode": "rule"],
        ], observer: ("local", "This machine"))
        let r = try F.reading([F.row("check.card", select: ["check": "lc-a"], engine)])
        return LocalChecksInput(reading: r, pins: [MonitorPin(kind: .check, id: "lc-a")])
    }

    /// A capture from a real `topo` and mihomo engine (a synthetic
    /// configuration in a container): see the fixtures' README.
    func captured(_ name: String) throws -> (LocalChecksInput, Date) {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/local-\(name).ndjson")
        let line = try Data(contentsOf: url)
        let f = try #require(FrameDecoder.frame(from: line))
        let now = try #require(f.generatedAt)
        var p = ReaderPolicy(); p.receive(f, line: line, at: now)
        return (LocalChecksInput(reading: p.evaluate(at: now), pins: [MonitorPin(kind: .check, id: "lc-engine")]), now)
    }

    func card(_ name: String) throws -> ServiceCardModel {
        let (input, _) = try captured(name)
        var settings = Settings(); settings.sections.services = true
        let panel = SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: F.now), engine: .running, settings: settings, localChecks: input))
        return try #require(panel.services.first)
    }

    @Test func aWorkingEngineNamesTheServerItUses() throws {
        try L10n.with("en") {
            let ok = try card("ok")
            #expect(ok.mark == .up && ok.monitor?.summary == "Runtime matches policy")
            #expect(ok.monitor?.reading == "Reported route: test-net-a")
            #expect(ok.monitor?.subtitle == "This Mac · Core report")
            let fields = ok.monitor?.checks.first?.fields.map { "\($0.label)=\($0.value)" }
            #expect(fields == ["Policy=Matches", "Mode=rule", "TUN=Off"])
            // Expecting Global while the engine runs by rule.
            let policy = try card("policy")
            #expect(policy.mark == .degraded && policy.monitor?.summary == "Mode differs from policy")
            #expect(policy.monitor?.checks.first?.fields.first { $0.label == "Mode" }?.value == "rule · Expected global")
        }
    }

    @Test func anEngineThatStopsAnsweringSaysSoAndGoesDown() throws {
        try L10n.with("en") {
            let first = try card("stopped")
            #expect(first.monitor?.summary == "Proxy engine not answering" && first.mark == .degraded)
            #expect(first.monitor?.checks.first?.code == "adapter_api · network_error")
            let second = try card("stopped-down")
            #expect(second.monitor?.summary == "Proxy engine not answering" && second.mark == .down)
            // A secret the engine no longer takes is the monitor's problem, not an outage.
            let secret = try card("bad-secret")
            #expect(secret.monitor?.summary == "Controller rejected the token" && secret.mark == .unknown)
        }
        // Another kind's network error keeps the outcome's words.
        let other = MonitorWords.summary(try JSONDecoder().decode(ServiceCard.Check.self, from: Data(#"""
            {"id":"x","name":"x","kind":"http","health":"down","freshness":"fresh","diagnostic":{"outcome":"fail","evidence":"measured","stage":"connect","code":"network_error"}}
            """#.utf8)))
        #expect(L10n.with("en") { other } == MonitorWords.summary(try JSONDecoder().decode(ServiceCard.Check.self, from: Data(#"""
            {"id":"x","name":"x","kind":"http","health":"down","freshness":"fresh","diagnostic":{"outcome":"fail","evidence":"measured","stage":"connect","code":"other"}}
            """#.utf8))))
    }

    @Test func theEngineComesFirstUnderPinnedFromAnySource() throws {
        try L10n.with("en") {
            var settings = Settings()
            settings.sections.services = true
            settings.sections.monitors = [.init(kind: .check, id: "runtime")]
            let input = try local()
            let pin = MonitorPin(kind: .check, id: "lc-a")
            let panel = SectionBuilder.panel(PanelInput(reading: input.reading, engine: .running, settings: settings,
                                                        expandedMonitors: [pin], localChecks: input))
            let first = try #require(panel.services.first)
            #expect(first.monitor?.pin == pin && first.monitor?.expanded == true)
            #expect(first.monitor?.subtitle == "This Mac · Core report")
            #expect(first.monitor?.summary == "Runtime matches policy")
            #expect(first.monitor?.checks.first?.source.hasPrefix("This Mac") == true)

            // Reading Beszel or Komari directly: Pinned stays for the engine alone.
            settings.topo.source = "direct"; settings.topo.profile = "desktop"
            let direct = SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: F.now), engine: .running, settings: settings, localChecks: input))
            #expect(direct.services.map { $0.monitor?.pin } == [pin])
            let none = SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: F.now), engine: .running, settings: settings))
            #expect(none.services.isEmpty)
            // Pinned turned off hides it, as it hides every pin.
            settings.sections.services = false
            #expect(SectionBuilder.panel(PanelInput(reading: input.reading, engine: .running, settings: settings, localChecks: input)).services.isEmpty)
        }
    }
}
