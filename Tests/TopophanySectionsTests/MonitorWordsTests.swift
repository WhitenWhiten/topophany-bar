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

    @Test func aServiceCardCarriesTheDaysEdgeAccountAndItsNote() throws {
        try L10n.with("en") {
            let edge = F.check("w-site", diagnostic: ["outcome": "ok", "evidence": "measured", "stage": "http", "facts": [:] as [String: String]],
                               p50: 92, colo: "SEA", firstByte: "cached p50 12ms · p95 30ms · origin p50 98ms · p95 140ms")
            let card = try F.serviceCard(F.service("site", seenFrom: [("MacBook", [edge])], extra: [
                "answered_from": ["pops": ["SEA 62%", "NRT 38%"], "cache": ["DYNAMIC 80%", "HIT 20%"]],
                "memo": "Public site behind Cloudflare.",
            ]))
            #expect(card.answeredFrom == ["SEA 62%", "NRT 38%"] && card.cacheShares == ["DYNAMIC 80%", "HIT 20%"])
            #expect(card.firstByte == "cached p50 12ms · p95 30ms · origin p50 98ms · p95 140ms")
            #expect(card.memo == "Public site behind Cloudflare.")
            #expect(card.observers.first?.p95 == 115)
            // History keeps the note and drops the readings.
            let held = card.withheld(at: F.now)
            #expect(held.answeredFrom.isEmpty && held.cacheShares.isEmpty && held.firstByte.isEmpty && held.observers.first?.p95 == nil)
            #expect(held.memo == card.memo)
            // Nothing named, nothing said.
            let plain = try F.serviceCard(F.service("plain", seenFrom: [("MacBook", [F.check("p", diagnostic: nil)])]))
            #expect(plain.answeredFrom.isEmpty && plain.firstByte.isEmpty && plain.memo.isEmpty)
        }
    }

    @Test func onlyAWebRunbookOpens() throws {
        for good in ["https://wiki.example.invalid/runbooks/site", " http://runbooks.example.com/a?b=c "] {
            #expect(SectionBuilder.runbookURL(good) != nil, "\(good)")
        }
        for bad in ["", "wiki/runbooks/site", "file:///etc/hosts", "javascript:alert(1)", "ssh://host", "https://", "mailto:ops@example.com"] {
            #expect(SectionBuilder.runbookURL(bad) == nil, "\(bad)")
        }
        let card = try F.serviceCard(F.service("site", seenFrom: [("MacBook", [F.check("p", diagnostic: nil)])],
                                                extra: ["runbook": "https://wiki.example.invalid/runbooks/site"]))
        #expect(card.runbook?.host() == "wiki.example.invalid")
        // The runbook is the topology's, not a reading: history keeps it.
        #expect(card.withheld(at: F.now).runbook == card.runbook)
    }

    @Test func settingsGroupsProxyCoresAndTunnelsFirst() {
        let kinds = ["http", "mihomo", "dns", "zz-custom", "cloudflare", "http", "", "cloudflared", "mihomo", "host"]
        let groups = MonitorWords.grouped(Array(kinds.enumerated()), kind: \.element)
        #expect(groups.map(\.kind) == ["mihomo", "cloudflared", "cloudflare", "http", "dns", "host", "", "zz-custom"])
        // Items keep their order within a group.
        #expect(groups.first?.items.map(\.offset) == [1, 8])
        L10n.with("en") {
            #expect(MonitorWords.kindTitle("mihomo") == "mihomo (Clash.Meta)")
            #expect(MonitorWords.kindTitle("cloudflared") == "Cloudflare Tunnel connector")
            #expect(MonitorWords.kindTitle("tls") == "TLS")
            #expect(MonitorWords.kindTitle("") == "Other")
            #expect(MonitorWords.kindTitle("zz-custom") == "zz-custom")
        }
    }

    @Test func certificateAndLatencyPoliciesSayHowFarOff() throws {
        try L10n.with("en") {
            func cert(_ days: String) -> [String: Any] {
                F.check("tls-\(days)", health: "degraded", diagnostic: [
                    "outcome": "policy", "evidence": "measured", "stage": "tls_policy", "code": "certificate_expiring", "duration_ms": 92,
                    "facts": ["response_proof": "verified_https", "tls_days_remaining": days, "tls_not_after": "2026-11-10T07:00:00Z"],
                    "expected": ["tls_min_days": "14"],
                ])
            }
            let nine = try F.monitor(cert("9"))
            #expect(nine.summary == "Certificate expires in 9 days")
            // The day it expires where the Mac is, so not fixed here.
            let expires = try #require(F.field(nine, "Certificate expires"))
            #expect(expires.hasPrefix("Nov ") && expires.hasSuffix(", 2026 · in 9 days"), "\(expires)")
            #expect(F.field(nine, "Warns within") == "14 days")
            #expect(F.field(nine, "Latency budget") == nil)
            #expect(try F.monitor(cert("1")).summary == "Certificate expires tomorrow")
            #expect(try F.monitor(cert("0")).summary == "Certificate expires today")

            let slow = try F.monitor(F.check("api", health: "degraded", diagnostic: [
                "outcome": "policy", "evidence": "measured", "stage": "latency_policy", "code": "latency_exceeded", "duration_ms": 1430,
                "facts": ["response_proof": "verified_https", "edge_provider": "cloudflare", "edge_pop": "NRT"], "expected": ["max_duration_ms": "800"],
            ]))
            #expect(slow.summary == "Slower than its 800 ms budget")
            #expect(slow.reading == "took 1.43 s · NRT")
            #expect(F.field(slow, "Latency budget") == "800 ms" && F.field(slow, "Last request") == "1.43 s")
            // From an older topo: the code alone, no budget, no duration.
            let old = try F.monitor(F.check("old", health: "degraded", diagnostic: [
                "outcome": "policy", "evidence": "measured", "stage": "latency_policy", "code": "latency_exceeded", "facts": [:] as [String: String],
            ]))
            #expect(old.summary == "Slower than its latency budget" && old.reading.isEmpty)
        }
    }

    @Test func tailscaleReadsTheLocalStatusAndItsPing() throws {
        try L10n.with("en") {
            func peer(_ outcome: String, code: String = "", _ facts: [String: String]) -> [String: Any] {
                F.check("ts-\(code.isEmpty ? outcome : code)", kind: "tailscale", health: outcome == "ok" ? "up" : "unknown", diagnostic: [
                    "outcome": outcome, "evidence": "reported", "stage": "adapter", "code": code, "policy": "not_configured", "facts": facts,
                ])
            }
            let running = ["backend_state": "Running", "online_reported": "true", "active_reported": "true", "last_seen": "not reported",
                           "transport_hint": "direct_endpoint_reported"]
            let plain = try F.monitor(peer("ok", running))
            #expect(plain.summary == "Peer reported online; service unproven")
            #expect(plain.reading == "direct endpoint")
            // Online and not reported: no Last seen row.
            #expect(plain.checks.first?.fields.map(\.label) == ["Policy", "Tailscale", "Online", "Active", "Path"])
            #expect(F.field(plain, "Path") == "Direct endpoint reported")

            var pinged = running
            pinged.merge(["diagnostic_protocol": "tsmp", "diagnostic_response": "received", "diagnostic_route": "derp", "diagnostic_latency_ms": "48"]) { $1 }
            let ping = try F.monitor(peer("ok", pinged))
            #expect(ping.summary == "Peer answered a ping; service unproven")
            #expect(ping.reading == "ping 48 ms · via DERP")
            #expect(F.field(ping, "Ping") == "TSMP · 48 ms · via DERP")

            let offline = try F.monitor(peer("unknown", code: "peer_offline", [
                "backend_state": "Running", "online_reported": "false", "active_reported": "false", "last_seen": "2026-11-01T04:37:46Z",
                "transport_hint": "relay_preference_reported", "health_warning_count": "2",
            ]))
            #expect(offline.summary == "Peer reported offline")
            #expect(offline.reading == "DERP relay · last seen 3 h ago")
            #expect(F.field(offline, "Active") == "Idle" && F.field(offline, "Last seen") == "3 h ago")
            #expect(F.field(offline, "Online") == "No" && F.field(offline, "Health warnings") == "2")

            let timedOut = try F.monitor(peer("unknown", code: "diagnostic_ping_timed_out", [
                "backend_state": "Running", "online_reported": "true", "active_reported": "false", "transport_hint": "unknown",
                "diagnostic_protocol": "disco", "diagnostic_response": "timed_out",
            ]))
            #expect(timedOut.summary == "Peer didn’t answer the ping")
            #expect(timedOut.reading == "ping timed out · idle")
            #expect(F.field(timedOut, "Ping") == "Disco · timed out" && F.field(timedOut, "Path") == "Not reported")

            let stopped = try F.monitor(peer("unknown", code: "backend_stopped", ["backend_state": "Stopped"]))
            #expect(stopped.summary == "Tailscale stopped" && stopped.reading.isEmpty)
            #expect(F.field(stopped, "Tailscale") == "Stopped")
            #expect(try F.monitor(peer("unknown", code: "peer_not_found", [:])).summary == "Peer not in this node’s status")
        }
    }

    @Test func wireguardReadsTheHandshakeAndCountersWithoutJudgingThem() throws {
        try L10n.with("en") {
            func peer(_ outcome: String, code: String = "", _ facts: [String: String], expected: [String: String] = [:]) -> [String: Any] {
                F.check("wg-\(code.isEmpty ? outcome : code)", kind: "wireguard", health: outcome == "ok" ? "up" : outcome == "policy" ? "degraded" : "unknown",
                        diagnostic: ["outcome": outcome, "evidence": "reported", "stage": "adapter", "code": code, "facts": facts, "expected": expected])
            }
            let ok = try F.monitor(peer("ok", [
                "sampling_atomicity": "separate_command_reads_not_atomic", "last_handshake": "2026-11-01T07:35:46Z",
                "rx_bytes": "1234567890", "tx_bytes": "340000000", "allowed_ips_match": "true", "keepalive_match": "true", "keepalive_seconds": "25",
            ], expected: ["keepalive_seconds": "25"]))
            #expect(ok.summary == "Peer counters read; tunnel unproven")
            #expect(ok.reading == "handshake 2 min ago · ↓ 1.2 GB ↑ 340 MB")
            #expect(F.field(ok, "Last handshake") == "2 min ago" && F.field(ok, "Received") == "1.2 GB" && F.field(ok, "Sent") == "340 MB")
            #expect(F.field(ok, "Snapshot") == "Two reads, not atomic")
            #expect(F.field(ok, "Allowed IPs") == "Matches" && F.field(ok, "Keepalive") == "25 s")

            let off = try F.monitor(peer("policy", code: "keepalive_mismatch", [
                "rx_bytes": "0", "tx_bytes": "0", "keepalive_match": "false", "keepalive_seconds": "0",
            ], expected: ["keepalive_seconds": "25"]))
            #expect(off.summary == "Keepalive differs from policy")
            #expect(off.reading == "no handshake yet · ↓ 0 B ↑ 0 B")
            #expect(F.field(off, "Keepalive") == "Off · Expected 25 s" && F.field(off, "Last handshake") == "None yet")

            let missing = try F.monitor(peer("unknown", code: "peer_not_found", ["sampling_atomicity": "separate_command_reads_not_atomic"]))
            #expect(missing.summary == "Peer not on the interface" && missing.reading.isEmpty)
            #expect(missing.checks.first?.fields.isEmpty == true)
            #expect(Words.bytes(999) == "999 B" && Words.bytes(999.5) == "1 kB")
        }
    }

    @Test func previewTailscaleCheckReadsItsStatus() throws {
        try L10n.with("en") {
            let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/assessment.ndjson")
            let line = try Data(contentsOf: url)
            let f = try #require(FrameDecoder.frame(from: line))
            let now = try #require(f.generatedAt)
            var p = ReaderPolicy(); p.receive(f, line: line, at: now)
            let pin = MonitorPin(kind: .check, id: "w-ts-transit")
            let card = try #require(SectionBuilder.monitors(p.evaluate(at: now), pins: [pin], expanded: [pin]).first?.monitor)
            #expect(card.summary == "Peer reported online; service unproven")
            #expect(card.reading == "direct endpoint")
            #expect(F.field(card, "Tailscale") == "Running" && F.field(card, "Active") == "Yes")
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
