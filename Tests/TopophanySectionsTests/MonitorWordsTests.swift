import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

/// What pinned checks say, from synthetic Topophany 1.5.2 diagnostics.
@Suite struct MonitorWordsTests {
    typealias F = MonitorFixtures

    static func mihomo(_ id: String, outcome: String = "ok", code: String = "", facts: [String: String] = ["mode": "rule"],
                       expected: [String: String] = [:], policy: String? = nil) -> [String: Any] {
        var d: [String: Any] = ["outcome": outcome, "evidence": "reported", "stage": "adapter", "code": code, "facts": facts, "expected": expected]
        if let policy { d["policy"] = policy }
        return F.check(id, kind: "mihomo", health: outcome == "ok" ? "up" : "degraded", diagnostic: d)
    }

    @Test func aRuntimeReadMatchesAPolicyOnlyWhenOneIsDeclared() throws {
        try L10n.with("en") {
            // No expectations and no provider comparison: nothing to match.
            let bare = try F.monitor(Self.mihomo("bare"))
            #expect(bare.summary == "Runtime reported; no policy declared")
            // Expectations or provider comparisons declare one, from an older topo too.
            let mode = try F.monitor(Self.mihomo("mode", expected: ["mode": "rule"]))
            #expect(mode.summary == "Runtime matches policy")
            let providers = try F.monitor(Self.mihomo("providers", facts: ["provider_comparison": "airport=match"]))
            #expect(providers.summary == "Runtime matches policy")
            // topo's own word wins over the inference, either way.
            let undeclared = try F.monitor(Self.mihomo("word", expected: ["mode": "rule"], policy: "not_configured"))
            #expect(undeclared.summary == "Runtime reported; no policy declared")
            #expect(F.field(undeclared, "Policy") == "None declared")
            let matched = try F.monitor(Self.mihomo("matched", policy: "matched"))
            #expect(matched.summary == "Runtime matches policy")
            #expect(F.field(matched, "Policy") == "Matches")
            let violated = try F.monitor(Self.mihomo("violated", outcome: "policy", code: "mode_mismatch", policy: "violated"))
            #expect(F.field(violated, "Policy") == "Differs")
        }
    }

    @Test func aPolicyFieldNeedsTopoToJudgeIt() throws {
        try L10n.with("en") {
            // An older topo sends no policy word: no field is invented.
            let old = try F.monitor(Self.mihomo("old", expected: ["mode": "rule"]))
            #expect(F.field(old, "Policy") == nil)
            let tunnel = try F.monitor(F.check("tunnel", kind: "cloudflared", diagnostic: [
                "outcome": "ok", "evidence": "reported", "stage": "adapter", "policy": "unverified",
                "facts": ["ready_connections": "4"], "expected": ["connections": "4"],
            ]))
            #expect(F.field(tunnel, "Policy") == "Not verified")
        }
    }

    static func edge(_ id: String, outcome: String = "ok", code: String = "", _ facts: [String: String]) -> [String: Any] {
        F.check(id, health: outcome == "ok" ? "up" : outcome == "fail" ? "down" : "degraded", diagnostic: [
            "outcome": outcome, "evidence": "measured", "stage": "http", "code": code,
            "facts": facts.merging(["edge_provider": "cloudflare", "response_proof": "verified_https"]) { a, _ in a },
        ], colo: facts["edge_pop"] ?? "")
    }

    @Test func theEdgeAnsweringInTheAppsPlaceIsNotAPass() throws {
        try L10n.with("en") {
            let access = try F.monitor(Self.edge("grafana", ["edge_pop": "NRT", "edge_access": "login_redirect"]))
            #expect(access.summary == "Access asked for a login; app not reached")
            // A status assertion failing on the redirect says the same.
            let failed = try F.monitor(Self.edge("grafana-200", outcome: "fail", code: "unexpected_status", ["edge_access": "login_redirect"]))
            #expect(failed.summary == "Access asked for a login; app not reached")
            // A challenge is named first, as topo's engine does.
            let both = try F.monitor(Self.edge("both", ["edge_mitigation": "challenge", "edge_access": "login_redirect"]))
            #expect(both.summary == "Edge served a challenge; app not reached")
            // A policy keeps its own words; the pill stays topo's.
            let policy = try F.monitor(Self.edge("pops", outcome: "policy", code: "pop_mismatch", ["edge_access": "login_redirect"]))
            #expect(policy.summary != "Access asked for a login; app not reached")
            let card = try F.card(Self.edge("pill", ["edge_access": "login_redirect"]))
            #expect(card.mark == .up)
        }
    }

    /// Every code topo's probes and adapters set, as (kind, outcome, code, words).
    static let named: [(String, String, String, String)] = [
        ("http", "policy", "certificate_expiring", "Certificate expires soon"),
        ("http", "policy", "latency_exceeded", "Slower than its latency budget"),
        ("http", "policy", "json_assertion_mismatch", "JSON response differs from its assertion"),
        ("http", "policy", "pop_mismatch", "Unexpected edge location"),
        ("http", "policy", "colo_mismatch", "Unexpected edge location"),
        ("http", "policy", "warp_mismatch", "WARP differs from policy"),
        ("http", "policy", "gateway_mismatch", "Gateway differs from policy"),
        ("http", "policy", "exit_mismatch", "Exit address differs from policy"),
        ("wireguard", "policy", "allowed_ips_mismatch", "Allowed IPs differ from policy"),
        ("wireguard", "policy", "keepalive_mismatch", "Keepalive differs from policy"),
        ("http", "fail", "body_mismatch", "Response didn’t match its assertion"),
        ("http", "fail", "header_mismatch", "Response didn’t match its assertion"),
        ("udp", "fail", "payload_mismatch", "Echo didn’t match what was sent"),
        ("mihomo", "error", "authentication_failed", "Controller rejected the token"),
        ("cloudflare", "error", "authentication_failed", "Cloudflare API rejected the token"),
        ("tailscale", "error", "authentication_failed", "Credentials rejected"),
        ("cloudflare", "error", "cloudflare_token_missing", "Token not set on the worker"),
        ("mihomo", "error", "adapter_secret_missing", "Token not set on the worker"),
        ("mihomo", "error", "reference_not_fresh", "Provider reference out of date"),
        ("mihomo", "error", "reference_unavailable", "Provider reference unavailable"),
        ("mihomo", "error", "invalid_reference_document", "Provider reference unusable"),
        ("mihomo", "unknown", "provider_reference_changed", "Provider reference changed while reading"),
        ("mihomo", "error", "proxy_inventory_capacity_exceeded", "Response too large to read"),
        ("cloudflare", "error", "unsupported_response_shape", "Response not recognized"),
        ("cloudflared", "error", "metrics_unavailable", "Connector metrics unavailable"),
        ("cloudflare", "error", "api_unavailable", "Cloudflare API unavailable"),
        ("mihomo", "unknown", "tun_state_unavailable", "TUN state not reported"),
    ]

    static func coded(_ kind: String, _ outcome: String, _ code: String) -> [String: Any] {
        F.check(code, kind: kind, health: outcome == "ok" ? "up" : outcome == "fail" ? "down" : outcome == "policy" ? "degraded" : "unknown",
                diagnostic: ["outcome": outcome, "evidence": "measured", "stage": "probe", "code": code, "facts": [:] as [String: String]])
    }

    @Test func probePoliciesAndMonitorErrorsAreNamed() throws {
        for (kind, outcome, code, words) in Self.named {
            let said = try L10n.with("en") { try F.monitor(Self.coded(kind, outcome, code)).summary }
            #expect(said == words, "\(kind) \(code)")
            // Translated, not left in English.
            for l in ["ja", "zh-Hans"] {
                let other = try L10n.with(l) { try F.monitor(Self.coded(kind, outcome, code)).summary }
                #expect(other != words, "\(l) \(code)")
            }
        }
    }

    @Test func aServiceTheEdgeAnsweredForSaysSo() throws {
        try L10n.with("en") {
            let plain = F.check("w-site", diagnostic: ["outcome": "ok", "evidence": "measured", "stage": "http", "facts": [:] as [String: String]])
            let access = Self.edge("t-site", ["edge_pop": "NRT", "edge_access": "login_redirect"])
            let card = try F.serviceCard(F.service("site", seenFrom: [("MacBook", [plain]), ("Tokyo", [access])]))
            #expect(card.diagnosticSummary == "Access asked for a login; app not reached")
            let calm = try F.serviceCard(F.service("calm", seenFrom: [("MacBook", [plain])]))
            #expect(calm.diagnosticSummary.isEmpty)
        }
    }
}
