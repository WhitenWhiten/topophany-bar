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

    @Test func mihomoProvidersReadInPlainWords() throws {
        try L10n.with("en") {
            let drift = try F.monitor(Self.mihomo("drift", outcome: "policy", code: "provider_membership_mismatch", facts: [
                "mode": "rule", "tun_enabled": "false", "core_delay_ms": "41", "core_last_checked": "2026-11-01T07:31:46Z",
                "provider.airport": "HK-02,JP-01,SG-01,US-01",
                "provider_comparison": "airport=mismatch(expected:4 loaded:4 missing:0 extra:0 order_changed:true present:true); backup=match(expected:2 loaded:2 missing:0 extra:0 order_changed:false present:true); gone=mismatch(expected:2 loaded:0 missing:2 extra:0 order_changed:false present:false); trim=mismatch(expected:3 loaded:2 missing:1 extra:1 order_changed:false present:true); cut=mismatch(expected:4 loa",
            ], expected: ["mode": "rule", "tun_enabled": "true"]))
            #expect(F.field(drift, "Mode") == "rule")
            #expect(F.field(drift, "TUN") == "Off · Expected On")
            #expect(F.field(drift, "Core last delay") == "41 ms · 6 min ago")
            #expect(F.field(drift, "airport") == "Order changed · HK-02, JP-01, SG-01, US-01")
            #expect(F.field(drift, "backup") == "Matches")
            #expect(F.field(drift, "gone") == "Not loaded")
            #expect(F.field(drift, "trim") == "1 missing · 1 extra")
            // The cut-off entry is dropped, not misread; the raw summary is gone.
            #expect(F.field(drift, "cut") == nil && F.field(drift, "Providers") == nil)
            #expect(drift.reading == "rule · TUN off")
            // A credential-bearing controller sends closed words only.
            let private_ = try F.monitor(Self.mihomo("private", outcome: "policy", code: "provider_membership_mismatch",
                                                      facts: ["provider_comparison": "airport=mismatch; backup=match"]))
            #expect(F.field(private_, "airport") == "Differs")
        }
    }

    @Test func aLoadingReferenceSaysHowFarAlongItIs() throws {
        try L10n.with("en") {
            let loading = try F.monitor(Self.mihomo("loading", outcome: "policy", code: "provider_membership_mismatch", facts: [
                "provider_reference_settling": "true", "provider_reference_published_at": "2026-11-01T07:35:46Z",
                "provider_updated_at.edge-local": "2026-11-01T07:20:46Z",
                "provider_comparison": "edge-local=settling(expected:3 loaded:2 missing:1 extra:0 order_changed:false present:true); fixed=unverified",
            ]))
            #expect(loading.summary == "Provider update loading")
            #expect(F.field(loading, "edge-local") == "Loading the published list · 2 of 3 loaded · last loaded 17 min ago")
            #expect(F.field(loading, "fixed") == "Not verified; the reference changed")
            #expect(F.field(loading, "Reference published") == "2 min ago")
            // A provider named like a field keeps its own row.
            let named = try F.monitor(Self.mihomo("named", facts: ["mode": "rule", "provider_comparison": "Mode=match"]))
            #expect(named.checks.first?.fields.filter { $0.label == "Mode" }.count == 2)
        }
    }

    static func reported(_ id: String, kind: String, outcome: String = "ok", code: String = "", _ facts: [String: String],
                         expected: [String: String] = [:]) -> [String: Any] {
        F.check(id, kind: kind, health: outcome == "ok" ? "up" : "degraded", diagnostic: [
            "outcome": outcome, "evidence": "reported", "stage": "adapter", "code": code, "facts": facts, "expected": expected,
        ])
    }

    @Test func cloudflaredSaysItsRedundancyTrafficAndVersion() throws {
        try L10n.with("en") {
            let m = try F.monitor(Self.reported("connector", kind: "cloudflared", [
                "ready_connections": "3", "ha_connections": "3", "connection_colos": "hkg,sin", "requests_total": "1200",
                "request_errors": "4", "active_streams": "2", "connector_version": "2026.10.0",
            ], expected: ["connections": "4", "colos": "hkg,nrt"]))
            #expect(m.reading == "3/4 connections · HKG, SIN")
            #expect(F.field(m, "HA connections") == "3")
            #expect(F.field(m, "Edge locations") == "HKG, SIN · Expected HKG, NRT")
            #expect(F.field(m, "Requests") == "1200 · 4 errors")
            #expect(F.field(m, "Active streams") == "2")
            #expect(F.field(m, "Version") == "2026.10.0")
            // Missing facts are unavailable, never zero.
            let bare = try F.monitor(Self.reported("bare", kind: "cloudflared", ["ready_connections": "4"]))
            #expect(bare.checks.first?.fields.isEmpty == true)
        }
    }

    @Test func theCloudflareAPISaysWhatItReported() throws {
        try L10n.with("en") {
            let tunnel = try F.monitor(Self.reported("api-tunnel", kind: "cloudflare", outcome: "policy", code: "connections_below_expected", [
                "tunnel_status": "degraded", "tunnel_connections": "2", "tunnel_colos": "HKG", "tunnel_pending_reconnect": "1",
                "connector_versions": "2026.9.1,2026.10.0", "oldest_connection_at": "2026-10-31T22:37:46Z",
            ], expected: ["connections": "4"]))
            #expect(tunnel.reading == "2/4 connections · HKG")
            #expect(F.field(tunnel, "Tunnel") == "Degraded")
            #expect(F.field(tunnel, "Reconnecting") == "1")
            #expect(F.field(tunnel, "Connector versions") == "2026.9.1, 2026.10.0")
            #expect(F.field(tunnel, "Oldest connection") == "opened 9 h ago")
            // Healthy with no connections list: the API's word is the reading.
            let moved = try F.monitor(Self.reported("moved", kind: "cloudflare", ["tunnel_status": "healthy"]))
            #expect(moved.reading == "Tunnel healthy")
            #expect(F.field(moved, "Reconnecting") == nil)

            let dns = try F.monitor(Self.reported("dns", kind: "cloudflare", outcome: "policy", code: "record_not_proxied", [
                "record_count": "1", "record_proxied": "false", "record_ttl": "1", "record_content_matches": "true",
            ], expected: ["record_proxied": "true"]))
            #expect(F.field(dns, "Proxied") == "No · Expected Yes")
            #expect(F.field(dns, "Content") == "Matches")
            #expect(F.field(dns, "TTL") == "Auto")
            let undeclared = try F.monitor(Self.reported("dns2", kind: "cloudflare", ["record_count": "2", "record_ttl": "300", "record_content_matches": "not_declared"]))
            #expect(F.field(undeclared, "Content") == nil && F.field(undeclared, "TTL") == "300 s")

            let pool = try F.monitor(Self.reported("pool", kind: "cloudflare", outcome: "policy", code: "origins_below_expected", [
                "pool_healthy": "false", "origins_healthy": "1", "origins_total": "2", "regions_reporting": "3",
                "origin.tokyo": "healthy", "origin.osaka": "unhealthy",
            ]))
            #expect(pool.reading == "1/2 origins healthy")
            #expect(F.field(pool, "Pool") == "Unhealthy")
            #expect(F.field(pool, "osaka") == "Unhealthy" && F.field(pool, "tokyo") == "Healthy")
            #expect(F.field(pool, "Regions reporting") == "3")
        }
    }

    @Test func edgeAndTraceChecksSayWhatTheEdgeReported() throws {
        try L10n.with("en") {
            let edge = try F.card(Self.edge("www", ["edge_pop": "NRT", "edge_cache": "HIT", "edge_rtt_ms": "12"]))
            #expect(edge.monitor?.reading == "NRT · HIT · edge RTT 12 ms")
            #expect(edge.host.provider == "Cloudflare")
            let fast = try F.monitor(Self.edge("fast", ["edge_pop": "SEA", "edge_rtt_ms": "0"]))
            #expect(fast.reading == "SEA · edge RTT <1 ms")
            let trace = try F.card(F.check("trace", health: "degraded", diagnostic: [
                "outcome": "policy", "evidence": "measured", "stage": "trace_assert", "code": "warp_mismatch",
                "facts": ["trace_colo": "SEA", "trace_warp": "off", "trace_gateway": "off", "trace_http": "http/2", "trace_tls": "TLSv1.3"],
            ]))
            #expect(trace.monitor?.summary == "WARP differs from policy")
            #expect(trace.monitor?.reading == "SEA · WARP off · Gateway off")
            #expect(trace.monitor?.checks.first?.fields.map(\.value) == ["http/2", "TLSv1.3"])
            #expect(trace.host.provider == "Cloudflare")
        }
    }

    static func policy(_ id: String, _ code: String, observer: (id: String, name: String), outcome: String = "policy") -> [String: Any] {
        F.check(id, health: outcome == "fail" ? "down" : outcome == "error" ? "unknown" : "degraded", diagnostic: [
            "outcome": outcome, "evidence": "measured", "stage": "probe", "code": code, "facts": [:] as [String: String],
        ], observer: observer)
    }

    @Test func aServiceCardListsEveryDiagnosisOnce() throws {
        try L10n.with("en") {
            let mac = ("obs-mac", "Seattle MacBook"), tokyo = ("obs-tokyo", "Tokyo VPS"), win = ("obs-win", "Seattle Windows")
            let card = try F.serviceCard(F.service("site", health: "down", seenFrom: [
                ("MacBook", [Self.policy("w-tls", "certificate_expiring", observer: mac), Self.policy("w-tls-2", "certificate_expiring", observer: mac)]),
                ("Tokyo", [Self.policy("t-api", "latency_exceeded", observer: tokyo), Self.policy("t-down", "body_mismatch", observer: tokyo, outcome: "fail")]),
                ("Windows", [Self.policy("w-json", "json_assertion_mismatch", observer: win), Self.policy("w-auth", "authentication_failed", observer: win, outcome: "error")]),
            ]))
            // Failures first, then monitor errors, then policies; a repeat once.
            #expect(card.diagnoses.map { "\($0.label): \($0.text)" } == [
                "Tokyo: Response didn’t match its assertion",
                "Windows: Credentials rejected",
                "MacBook: Certificate expires soon",
                "Tokyo: Slower than its latency budget",
                "Windows: JSON response differs from its assertion",
            ])
            #expect(card.diagnosticSummary == "Response didn’t match its assertion")
            #expect(card.diagnoses.first?.mark == .down)
            // Past the card's deadline, nothing is said.
            #expect(card.withheld(at: F.now).diagnoses.isEmpty)
        }
    }

    @Test func aLatencyFitsItsColumn() {
        let cases: [(Double, String)] = [(4, "4 ms"), (46.4, "46 ms"), (999.4, "999 ms"), (999.6, "1.00 s"), (1430, "1.43 s"),
                                         (9994, "9.99 s"), (9996, "10.0 s"), (14_320, "14.3 s"), (99_960, "100 s"), (143_000, "143 s")]
        for (ms, text) in cases {
            #expect(Words.latency(ms) == text, "\(ms)")
            #expect(Words.latency(ms).count <= 6, "\(ms)")
        }
        #expect(Words.latencyParts(1430) == ("1.43", "s"))
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
