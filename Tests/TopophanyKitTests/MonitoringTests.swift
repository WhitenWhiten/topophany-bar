import Foundation
import Testing
@testable import TopophanyKit

@Suite struct MonitoringTests {
    let at = Timestamp.parse("2026-11-01T10:00:00Z")!
    let raw = #"{"schema":1,"source":"client","project":"lab","observer":"mac","instance":"one","sequence":1,"lifecycle":"running","generated_at":"2026-11-01T10:00:00Z","publisher_expires_at":"2026-11-01T10:00:30Z","collector_read":{"state":"ok","completed_at":"2026-11-01T10:00:00Z","last_success_at":"2026-11-01T10:00:00Z","duration_ms":12,"consecutive_failures":0},"rows":[{"id":"link","metric":"link.card","select":{"link":"tunnel"},"health":"up","valid_until":"2026-11-01T10:00:25Z","value":{"id":"tunnel","from":{"id":"host","name":"Host"},"to":{"id":"edge","name":"Edge"},"health":"up","evidence":"reported","checks":[{"id":"api","kind":"cloudflare","health":"degraded","freshness":"fresh","sampled_at":"2026-11-01T10:00:00Z","valid_until":"2026-11-01T10:00:02Z","observer":{"id":"mac","name":"Mac"},"diagnostic":{"outcome":"policy","evidence":"reported","code":"connections_below_expected","facts":{"tunnel_connections":"1"},"expected":{"connections":"4"}}}]}}]}"#

    @Test func nestedDiagnosticsExpireWithoutExpiringLink() throws {
        let frame = try JSONDecoder().decode(Frame.self, from: Data(raw.utf8))
        #expect(frame.collectorRead?.durationMS == 12)
        var policy = ReaderPolicy()
        policy.receive(frame, at: at)
        guard case .linkCard(let before) = policy.evaluate(at: at).rows[0].value,
              case .linkCard(let after) = policy.evaluate(at: at.addingTimeInterval(3)).rows[0].value else {
            Issue.record("link did not decode"); return
        }
        #expect(before.checks[0].check.diagnostic?.expected["connections"] == "4")
        #expect(after.summary.health == .up)
        #expect(after.checks[0].check.health == .unknown)
        #expect(after.checks[0].check.diagnostic == nil)
        #expect(policy.evaluate(at: at.addingTimeInterval(25)).rows[0].value == .none)
    }

    @Test func cacheIdentityIncludesSelectorAndScope() throws {
        var frame = try JSONDecoder().decode(Frame.self, from: Data(raw.utf8))
        var policy = ReaderPolicy()
        policy.receive(frame, at: at)
        var other = frame.rows[0]
        other.select?.link = "other"
        other.value = .none
        #expect(policy.evaluate(at: at).lastValue(of: .init(row: other, status: .withheld(.noValue))) == .none)
        frame.sequence = 2; frame.observer = "s2"; frame.rows = [other]
        policy.receive(frame, at: at)
        #expect(policy.lastValues.isEmpty)
    }

    @Test func unsupportedOptionsAreOmitted() throws {
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"metrics":[{"name":"summary.verdict"}]}"#.utf8))
        var request = Request(requestID: "r", template: Template(rows: [.init(id: "status", metric: "summary.verdict", visual: "status", history: false)]))
        request.retryNonce = "retry"
        let supported = request.supported(by: caps)
        #expect(!caps.collectorRead && !caps.clientRetry && !caps.cardHistory)
        #expect(supported.retryNonce == nil)
        #expect(supported.template.rows[0].history == nil)
        #expect(!String(decoding: try supported.line(), as: UTF8.self).contains("retry_nonce"))
    }

    @Test func unpinnedIdentityIsReleasedWithoutDroppingUnavailableHistory() throws {
        var frame = try JSONDecoder().decode(Frame.self, from: Data(raw.utf8))
        var policy = ReaderPolicy(); policy.receive(frame, at: at)
        frame.sequence = 2; frame.rows[0].value = .none
        policy.receive(frame, at: at)
        #expect(policy.lastValues.count == 1)
        frame.sequence = 3; frame.rows[0].select?.link = "another-link"
        policy.receive(frame, at: at)
        #expect(policy.lastValues.isEmpty)
    }
}
