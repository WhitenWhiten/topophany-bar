import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

struct DirectSectionTests {
    @Test func failingSourcesLeadWithoutReorderingTheirPeers() throws {
        let data = Data(#"{"state":"partial","sources":[{"id":"a","state":"connected","counts":{"selected":1,"current":1}},{"id":"b","state":"loading"},{"id":"c","state":"retrying","code":"rate_limited","next_retry_at":"2026-10-21T12:01:00Z"},{"id":"d","state":"connected","counts":{"stale":1}},{"id":"e","state":"auth_required"}]}"#.utf8)
        let value = try JSONDecoder().decode(SourcesStatus.self, from: data)
        let section = SourceStatusSection(value: value, isCurrent: true)
        #expect(section.value.sources.map(\.id) == ["c", "e", "d", "a", "b"])
        #expect(SourceStatusSection(value: value, isCurrent: false).value.sources.map(\.id) == ["a", "b", "c", "d", "e"])
        let limited = section.value.sources[0]
        L10n.with("en") {
            #expect(section.detail(limited) == "Rate limited")
            #expect(SourceMessages.diagnostic(limited).contains("Next retry:"))
            var connected = limited; connected.state = "connected"; connected.code = nil
            #expect(!SourceMessages.diagnostic(connected).contains("Next retry:"))
        }
        #expect(section.mark(limited) == .degraded)
        #expect(section.mark(section.value.sources[2]) == .up, "expired samples do not imply lost contact")
    }

    @Test func expiredSamplesKeepSourceContactAndExplainTheirReason() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/contracts/direct-v1/fixtures")
        let frame = try #require(FrameDecoder.frame(from: Data(contentsOf: root.appending(path: "stream-expired.json"))))
        let now = try #require(frame.generatedAt)
        var policy = ReaderPolicy(); policy.receive(frame, at: now)
        let status = SectionBuilder.status(policy.evaluate(at: now), engine: .running)
        #expect(status.sources?.value.reason == "samples_stale")
        #expect(status.sources?.value.sources.first?.state == "connected")
        #expect(L10n.with("en") { status.title } == "Readings expired")
        #expect(L10n.with("zh-Hans") { status.title } == "读数已过期")
        #expect(status.count == 1 && status.verdictState == nil)
    }

    @Test func statesPreserveBackendSemantics() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/DirectDevelopment")
        let now = Timestamp.parse("2026-10-21T12:00:00Z")!
        for name in ["loading", "ready", "partial", "no_data", "auth_required", "forbidden", "retrying", "unknown"] {
            let frame = try #require(FrameDecoder.frame(from: Data(contentsOf: root.appending(path: name + ".json"))))
            var policy = ReaderPolicy(); policy.receive(frame, at: now)
            var settings = Settings(); settings.topo.source = "direct"; settings.sections.servers = true
            settings.sections.serverNodes = [frame.rows.last!.select!.node!]
            let panel = SectionBuilder.panel(.init(reading: policy.evaluate(at: now), engine: .running, settings: settings))
            #expect(panel.status.verdictState == nil)
            #expect(panel.status.sources != nil)
            #expect(panel.chrome.connection == .direct)
            #expect(L10n.with("en") { panel.chrome.connectionText.hasPrefix("topo running") })
            #expect(!panel.status.title.contains("All clear"))
            #expect(panel.seen == nil && panel.map == nil && panel.services.isEmpty && panel.zones == nil)
            #expect(panel.status.count == (name == "ready" || name == "partial" ? nil : 1))
            if name == "ready" {
                #expect(panel.servers.first?.cpu.percent == 27.5)
                #expect(panel.servers.first?.origin?.badge == "Beszel")
                #expect(panel.servers.first?.provider == "")
            }
            let expired = SectionBuilder.status(policy.evaluate(at: now.addingTimeInterval(181)), engine: .running)
            #expect(expired.isBlind && expired.mark == .offline && expired.count == nil)
        }
    }
    /// A Komari source's problems speak of its server and API key; the
    /// profile's own stay the same for either adapter.
    @Test func problemsNameTheAdapter() {
        L10n.with("en") {
            #expect(SourceMessages.problem("connection_failed") == "Could not reach the Beszel Hub. Check the address and try again.")
            #expect(SourceMessages.problem("connection_failed", adapter: "komari") == "Could not reach the Komari server. Check the address and try again.")
            #expect(SourceMessages.problem("profile_conflict", adapter: "komari") == SourceMessages.problem("profile_conflict"))
        }
        for code in ["hub_changed", "auth_required", "forbidden", "auth_method_unsupported", "connection_failed", "tls_error", "rate_limited", "upstream_incompatible", "discovery_limit"] {
            let english = L10n.with("en") { SourceMessages.problem(code, adapter: "komari") }
            for language in ["ja", "zh-Hans"] {
                #expect(L10n.with(language) { SourceMessages.problem(code, adapter: "komari") } != english, "\(code) in \(language)")
            }
        }
    }
}
