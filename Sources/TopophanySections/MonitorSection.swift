import Foundation
import TopophanyKit

/// Compact checks and links share the existing pinned-card surface. Detailed
/// evidence is prepared here once per data update, never inside drawing code.
public struct MonitorCardModel: Sendable, Hashable {
    public struct Field: Sendable, Hashable, Identifiable {
        public var label: String
        public var value: String
        /// Unique within a check: a provider may share a label's name.
        public var key: String
        public var id: String { key }
        public init(label: String, value: String, key: String? = nil) {
            self.label = label
            self.value = value
            self.key = key ?? label
        }
    }
    public struct Check: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var source: String
        public var mark: Mark
        public var summary: String
        public var reading: String
        public var code: String
        public var history: ServiceCardModel.History
        public var p50: Double?
        public var p50Label: String
        public var fields: [Field]
        public var up24h: Double?
    }
    public var pin: MonitorPin
    public var subtitle: String
    public var summary: String
    public var reading: String
    public var checks: [Check]
    public var expanded: Bool
}

public enum MonitorWords {
    public static func evidence(_ value: String) -> String {
        switch value {
        case "reported": tr("Reported")
        case "measured": tr("Measured")
        case "inferred": tr("Inferred")
        default: tr("Evidence incomplete")
        }
    }

    /// What answered in the application's place, when the edge in front
    /// did: a challenge page, or Cloudflare Access asking for a login. Either
    /// way the origin was not asked, whatever the check's outcome says.
    public static func edgeStandIn(_ d: CheckDiagnostic) -> String? {
        if d.facts["edge_mitigation"] == "challenge" { return tr("Edge served a challenge; app not reached") }
        if d.facts["edge_access"] == "login_redirect" { return tr("Access asked for a login; app not reached") }
        return nil
    }

    public static func summary(_ c: ServiceCard.Check) -> String {
        guard let d = c.diagnostic else { return tr("Not known now") }
        // A passing or failing request the edge answered says nothing of the
        // app; a policy or monitor error keeps its own words.
        if d.outcome == "ok" || d.outcome == "fail", let standIn = edgeStandIn(d) { return standIn }
        switch d.code {
        case "tunnel_not_ready": return tr("No tunnel session")
        case "connections_below_expected": return tr("Fewer connections than expected")
        case "colo_outside_expected": return tr("Unexpected edge location")
        case "mode_mismatch": return tr("Mode differs from policy")
        case "tun_mismatch": return tr("TUN differs from policy")
        case "provider_membership_mismatch":
            return d.facts["provider_reference_settling"] == "true" ? tr("Provider update loading") : tr("Provider membership differs")
        case "runtime_chain_unresolved": return tr("Reported route unresolved")
        case "record_missing": return tr("DNS record missing")
        case "record_content_mismatch", "record_not_proxied", "record_proxied_unexpectedly": return tr("DNS differs from policy")
        case "origins_below_expected": return tr("Fewer healthy origins than expected")
        // Probe policies: the request succeeded, against a declared policy.
        case "certificate_expiring":
            guard let days = d.facts["tls_days_remaining"].flatMap(Int.init) else { return tr("Certificate expires soon") }
            return days <= 0 ? tr("Certificate expires today") : days == 1 ? tr("Certificate expires tomorrow") : tr("Certificate expires in \(days) days")
        case "latency_exceeded":
            guard let budget = d.expected["max_duration_ms"].flatMap(Double.init) else { return tr("Slower than its latency budget") }
            return tr("Slower than its \(Words.latency(budget)) budget")
        case "json_assertion_mismatch": return tr("JSON response differs from its assertion")
        case "pop_mismatch", "colo_mismatch": return tr("Unexpected edge location")
        case "warp_mismatch": return tr("WARP differs from policy")
        case "gateway_mismatch": return tr("Gateway differs from policy")
        case "exit_mismatch": return tr("Exit address differs from policy")
        case "allowed_ips_mismatch": return tr("Allowed IPs differ from policy")
        case "keepalive_mismatch": return tr("Keepalive differs from policy")
        // Failed assertions on what answered.
        case "body_mismatch", "regex_mismatch", "header_mismatch": return tr("Response didn’t match its assertion")
        case "payload_mismatch": return tr("Echo didn’t match what was sent")
        // The monitor's own reads: never the service's state.
        case "authentication_failed":
            switch c.kind {
            case "mihomo": return tr("Controller rejected the token")
            case "cloudflare": return tr("Cloudflare API rejected the token")
            default: return tr("Credentials rejected")
            }
        case "adapter_secret_missing", "cloudflare_token_missing", "reference_secret_missing": return tr("Token not set on the worker")
        case "reference_unavailable", "reference_transport_unavailable": return tr("Provider reference unavailable")
        case "reference_not_fresh": return tr("Provider reference out of date")
        case "invalid_reference_document", "invalid_reference_members", "reference_provider_missing",
             "reference_complexity_exceeded", "reference_response_limit_exceeded": return tr("Provider reference unusable")
        case "provider_reference_changed": return tr("Provider reference changed while reading")
        case "proxy_inventory_capacity_exceeded", "proxy_members_capacity_exceeded", "provider_evidence_budget_exceeded",
             "response_limit_exceeded", "response_complexity_exceeded", "response_too_large": return tr("Response too large to read")
        case "unsupported_response_shape": return tr("Response not recognized")
        case "metrics_unavailable": return tr("Connector metrics unavailable")
        case "api_unavailable": return tr("Cloudflare API unavailable")
        case "tun_state_unavailable": return tr("TUN state not reported")
        // The engine's status API didn't answer: usually the proxy app isn't running.
        case "network_error" where c.kind == "mihomo", "timeout" where c.kind == "mihomo": return tr("Proxy engine not answering")
        case "unexpected_status" where c.kind == "mihomo": return tr("Proxy engine answered with an error")
        // Tailscale and WireGuard: what this observer's own runtime reports.
        case "backend_needs_login": return tr("Tailscale needs a login")
        case "backend_needs_machine_auth": return tr("Tailscale awaits device approval")
        case "backend_stopped": return tr("Tailscale stopped")
        case "backend_not_ready": return tr("Tailscale starting")
        case "unsupported_backend_state": return tr("Tailscale state not recognized")
        case "peer_offline": return tr("Peer reported offline")
        case "peer_online_unavailable": return tr("Peer’s online state not reported")
        case "peer_not_found": return c.kind == "wireguard" ? tr("Peer not on the interface") : tr("Peer not in this node’s status")
        case "ambiguous_peer": return tr("More than one peer matches")
        case "peer_snapshot_changed": return tr("Peers changed while reading")
        case "peer_diagnostic_ip_unavailable": return tr("Peer has no address to ping")
        case "diagnostic_ping_timed_out": return tr("Peer didn’t answer the ping")
        case "diagnostic_timeout", "diagnostic_canceled": return tr("Ping didn’t finish")
        case "tailscale_unavailable_or_permission_denied": return tr("Tailscale not readable by the monitor")
        case "wireguard_unavailable_or_permission_denied": return tr("WireGuard not readable by the monitor")
        case "command_not_found": return tr("Command not found on the worker")
        case "command_permission_denied": return tr("Command not permitted on the worker")
        case "unsupported_tailscale_response", "unsupported_tailscale_diagnostic_response", "unsupported_wireguard_response",
             "invalid_handshake_timestamp", "invalid_transfer_counter", "invalid_allowed_ips", "invalid_keepalive_interval":
            return tr("Response not recognized")
        default: break
        }
        if d.facts["provider_reference_settling"] == "true" { return tr("Provider update loading") }
        switch d.outcome {
        case "error": return tr("Monitor could not read evidence")
        case "fail": return tr("Check failed")
        case "policy": return tr("Policy differs")
        case "ok":
            if c.kind == "cloudflared" { return tr("Tunnel established; service unproven") }
            if c.kind == "mihomo" { return declaresPolicy(d) ? tr("Runtime matches policy") : tr("Runtime reported; no policy declared") }
            // Reported by the local runtime; neither proves the service.
            if c.kind == "tailscale" {
                return d.facts["diagnostic_response"] == "received" ? tr("Peer answered a ping; service unproven") : tr("Peer reported online; service unproven")
            }
            if c.kind == "wireguard" { return tr("Peer counters read; tunnel unproven") }
            return d.evidence == "reported" ? tr("Reported check passing") : tr("Check passing")
        default: return tr("Evidence incomplete")
        }
    }

    /// Check kinds and link transports in the order Settings groups them:
    /// proxy cores and tunnels first, then protocols, then everything else.
    static let kindOrder = ["mihomo", "cloudflared", "cloudflare", "tailscale", "wireguard", "http", "tls", "tcp", "dns", "icmp", "host", "external"]

    /// A check kind or link transport as Settings titles its group.
    public static func kindTitle(_ kind: String) -> String {
        switch kind {
        case "mihomo": tr("mihomo (Clash.Meta)")
        case "cloudflared": tr("Cloudflare Tunnel connector")
        case "cloudflare": tr("Cloudflare API")
        case "tailscale": "Tailscale"
        case "wireguard": "WireGuard"
        case "http", "tls", "tcp", "dns": kind.uppercased()
        case "icmp": tr("Ping")
        case "host": tr("Host resources")
        case "external": tr("External sources")
        case "": tr("Other")
        default: kind
        }
    }

    /// `items` grouped by `kind`, groups in `kindOrder` then by name, items
    /// in their given order.
    public static func grouped<T>(_ items: [T], kind: (T) -> String) -> [(kind: String, items: [T])] {
        var groups: [String: [T]] = [:]
        for item in items { groups[kind(item), default: []].append(item) }
        func rank(_ k: String) -> (Int, String) { (kindOrder.firstIndex(of: k) ?? kindOrder.count, k) }
        return groups.keys.sorted { rank($0) < rank($1) }.map { ($0, groups[$0] ?? []) }
    }

    /// Whether the check declares a policy at all: `topo`'s own word when it
    /// sends one, else what its expectations show. A runtime read with none
    /// matches nothing.
    public static func declaresPolicy(_ d: CheckDiagnostic) -> Bool {
        if !d.policy.isEmpty { return d.policy != "not_configured" }
        return !d.expected.isEmpty || d.facts.keys.contains { $0 == "provider_comparison" || $0.hasPrefix("provider_reference_") }
    }

    /// `topo`'s judgment of an adapter check's declared policy, as a field.
    static func policyField(_ d: CheckDiagnostic) -> MonitorCardModel.Field? {
        let value: String
        switch d.policy {
        case "matched": value = tr("Matches")
        case "violated": value = tr("Differs")
        case "unverified": value = tr("Not verified")
        case "not_configured": value = tr("None declared")
        default: return nil
        }
        return .init(label: tr("Policy"), value: value)
    }

    /// The expanded card's readings, once per data update: ages are as of
    /// `now`, the reading's own clock.
    public static func fields(_ c: ServiceCard.Check, now: Date) -> [MonitorCardModel.Field] {
        guard let d = c.diagnostic else { return [] }
        var out: [MonitorCardModel.Field] = policyField(d).map { [$0] } ?? []
        switch c.kind {
        case "mihomo": out += mihomoFields(d, now: now)
        case "cloudflared": out += cloudflaredFields(d)
        case "cloudflare": out += cloudflareFields(d, now: now)
        case "tailscale": out += tailscaleFields(d, now: now)
        case "wireguard": out += wireguardFields(d, now: now)
        default: out += traceFields(d) + probePolicyFields(d)
        }
        return out
    }

    static func days(_ n: Int) -> String { n == 1 ? tr("1 day") : tr("\(n) days") }

    /// 1.5.2's probe policies, against what the check measured: the
    /// certificate's expiry and warning window, the latency budget and the
    /// newest request's duration.
    static func probePolicyFields(_ d: CheckDiagnostic) -> [MonitorCardModel.Field] {
        var out: [MonitorCardModel.Field] = []
        if let notAfter = d.facts["tls_not_after"].flatMap(Timestamp.parse) {
            let left = d.facts["tls_days_remaining"].flatMap(Int.init).map { $0 <= 0 ? tr("today") : tr("in \(days($0))") } ?? ""
            out.append(.init(label: tr("Certificate expires"),
                             value: Words.join([notAfter.formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale)), left])))
        }
        if let window = d.expected["tls_min_days"].flatMap(Int.init) { out.append(.init(label: tr("Warns within"), value: days(window))) }
        if let budget = d.expected["max_duration_ms"].flatMap(Double.init) {
            out.append(.init(label: tr("Latency budget"), value: Words.latency(budget)))
            if let took = d.durationMS { out.append(.init(label: tr("Last request"), value: Words.latency(Double(took)))) }
        }
        return out
    }

    /// mihomo's mode, as its apps name it.
    public static func modeName(_ mode: String) -> String {
        switch mode {
        case "rule": tr("Rule mode")
        case "global": tr("Global mode")
        case "direct": tr("Direct mode")
        default: mode
        }
    }

    static func onOff(_ value: String) -> String {
        switch value {
        case "true": tr("On")
        case "false": tr("Off")
        default: value
        }
    }

    /// `text`, and what was expected where that differs.
    static func expecting(_ d: CheckDiagnostic, _ key: String, _ text: String, shown: (String) -> String = { $0 }) -> String {
        guard let e = d.expected[key], e != d.facts[key] else { return text }
        return Words.join([text, tr("Expected \(shown(e))")])
    }

    static func mihomoFields(_ d: CheckDiagnostic, now: Date) -> [MonitorCardModel.Field] {
        let f = d.facts
        var out: [MonitorCardModel.Field] = []
        if let mode = f["mode"], !mode.isEmpty { out.append(.init(label: tr("Mode"), value: expecting(d, "mode", mode))) }
        if let tun = f["tun_enabled"], !tun.isEmpty { out.append(.init(label: "TUN", value: expecting(d, "tun_enabled", onOff(tun), shown: onOff))) }
        if let delay = f["core_delay_ms"], !delay.isEmpty {
            // The core's own last test, as old as it says: never fresh by implication.
            let checked = f["core_last_checked"].flatMap(Timestamp.parse)
            out.append(.init(label: tr("Core last delay"), value: Words.join([delay + " ms", checked.map { Words.ago($0, now: now) } ?? ""])))
        }
        for p in ProviderComparison.parse(f["provider_comparison"] ?? "") {
            out.append(.init(label: p.name, value: p.words(members: f["provider." + p.name],
                                                           loadedAt: f["provider_updated_at." + p.name].flatMap(Timestamp.parse), now: now),
                             key: "provider." + p.name))
        }
        if let published = f["provider_reference_published_at"].flatMap(Timestamp.parse) {
            out.append(.init(label: tr("Reference published"), value: Words.ago(published, now: now)))
        }
        return out
    }

    /// One provider in mihomo's `provider_comparison`: `name=status`, with
    /// `(expected:4 loaded:4 missing:0 extra:0 order_changed:true present:true)`
    /// from a controller that sends its details. A summary cut at topo's fact
    /// budget loses its last, partial entry rather than misreading it.
    struct ProviderComparison: Equatable {
        var name: String
        var status: String
        var details: [String: String]

        static let statuses: Set<String> = ["match", "mismatch", "settling", "unverified"]

        static func parse(_ summary: String) -> [ProviderComparison] {
            summary.components(separatedBy: "; ").compactMap { entry in
                var head = Substring(entry)
                var details: [String: String] = [:]
                if entry.hasSuffix(")"), let open = entry.lastIndex(of: "(") {
                    head = entry[..<open]
                    for pair in entry[entry.index(after: open)..<entry.index(before: entry.endIndex)].split(separator: " ") {
                        let kv = pair.split(separator: ":", maxSplits: 1)
                        if kv.count == 2 { details[String(kv[0])] = String(kv[1]) }
                    }
                }
                guard let eq = head.lastIndex(of: "=") else { return nil }
                let name = String(head[..<eq]), status = String(head[head.index(after: eq)...])
                guard !name.isEmpty, statuses.contains(status) else { return nil }
                return ProviderComparison(name: name, status: status, details: details)
            }
        }

        func count(_ key: String) -> Int? { details[key].flatMap(Int.init) }

        func words(members: String?, loadedAt: Date?, now: Date) -> String {
            switch status {
            case "match": return tr("Matches")
            case "settling":
                var parts = [tr("Loading the published list")]
                if let loaded = count("loaded"), let expected = count("expected") { parts.append(tr("\(loaded) of \(expected) loaded")) }
                if let loadedAt { parts.append(tr("last loaded \(Words.ago(loadedAt, now: now))")) }
                return Words.join(parts)
            case "unverified": return tr("Not verified; the reference changed")
            default:
                if details["present"] == "false" { return tr("Not loaded") }
                var parts: [String] = []
                if let n = count("missing"), n > 0 { parts.append(tr("\(n) missing")) }
                if let n = count("extra"), n > 0 { parts.append(tr("\(n) extra")) }
                if details["order_changed"] == "true" { parts.append(tr("Order changed")) }
                if parts.isEmpty { parts.append(tr("Differs")) }
                // What the core loaded, in its order: names topo already showed.
                if let members, !members.isEmpty { parts.append(members.replacingOccurrences(of: ",", with: ", ")) }
                return Words.join(parts)
            }
        }
    }

    /// At most two relevant readings; missing values are never interpreted
    /// as zero. Ages are as of `now`, the reading's own clock.
    public static func reading(_ c: ServiceCard.Check, now: Date) -> String {
        guard let d = c.diagnostic else { return "" }
        let f = d.facts
        if c.kind == "tailscale" {
            // A ping measured the route; otherwise the status's own hint.
            let path = switch f["diagnostic_response"] {
            case "received": Words.join([f["diagnostic_latency_ms"].flatMap(Double.init).map { tr("ping \(Words.latency($0))") } ?? "",
                                         pingRoute(f["diagnostic_route"] ?? "")])
            case "timed_out": tr("ping timed out")
            default: transportHint(f["transport_hint"] ?? "", short: true)
            }
            let presence = f["online_reported"] == "false" ? f["last_seen"].flatMap(Timestamp.parse).map { tr("last seen \(Words.ago($0, now: now))") } ?? ""
                : f["active_reported"] == "false" ? tr("idle") : ""
            return Words.join([path, presence])
        }
        if c.kind == "wireguard" {
            guard f["rx_bytes"] != nil || f["last_handshake"] != nil else { return "" }
            let handshake = f["last_handshake"].flatMap(Timestamp.parse).map { tr("handshake \(Words.ago($0, now: now))") } ?? tr("no handshake yet")
            let traffic = f["rx_bytes"].flatMap(Double.init).flatMap { rx in f["tx_bytes"].flatMap(Double.init).map { "↓ \(Words.bytes(rx)) ↑ \(Words.bytes($0))" } } ?? ""
            return Words.join([handshake, traffic])
        }
        if c.kind == "mihomo" {
            // `undeclared`: topo kept the names back, as for a secret sent to a collector's check.
            if let chain = f["reported_chain"], !chain.isEmpty, chain != "undeclared" { return tr("Reported route: \(chain.replacingOccurrences(of: " -> ", with: " → ").replacingOccurrences(of: "withheld_secret_request", with: tr("withheld")))") }
            let tun = f["tun_enabled"].map { $0 == "true" ? tr("TUN on") : $0 == "false" ? tr("TUN off") : "" } ?? ""
            return Words.join([f["mode"] ?? "", tun])
        }
        if let n = f["ready_connections"] ?? f["tunnel_connections"] {
            let count = d.expected["connections"].map { n + "/" + $0 } ?? n
            return Words.join([tr("\(count) connections"), colos(f["connection_colos"] ?? f["tunnel_colos"] ?? "")])
        }
        // The API reported the tunnel's state without its connections list.
        if let status = f["tunnel_status"] { return tunnelStatus(status) }
        if let n = f["origins_healthy"], let total = f["origins_total"] { return tr("\(n)/\(total) origins healthy") }
        if let n = f["record_count"] { return tr("\(n) DNS records") }
        // A trace check: the edge's account of this observer, reported, not verified.
        if f["trace_colo"] != nil || f["trace_warp"] != nil || f["trace_gateway"] != nil {
            return Words.join([f["trace_colo"] ?? "", f["trace_warp"].map { "WARP " + $0 } ?? "", f["trace_gateway"].map { "Gateway " + $0 } ?? ""])
        }
        // A request over its budget: how long it took, first.
        let took = d.code == "latency_exceeded" ? d.durationMS.map { tr("took \(Words.latency(Double($0)))") } ?? "" : ""
        return Words.join([took, f["edge_pop"] ?? "", f["edge_cache"] ?? "", edgeRTT(d).map { tr("edge RTT \($0)") } ?? ""])
    }

    /// Cloudflare's own round trip to the client, from `Server-Timing`'s
    /// `cfL4`, as the TUI writes it: "<1 ms" for zero.
    static func edgeRTT(_ d: CheckDiagnostic) -> String? {
        guard d.facts["edge_provider"] == "cloudflare", let raw = d.facts["edge_rtt_ms"], let ms = Int(raw), ms >= 0 else { return nil }
        return ms == 0 ? "<1 ms" : Words.ms(Double(ms))
    }

    /// Colo tokens as colos are written: "HKG, SIN".
    static func colos(_ list: String) -> String {
        list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func tunnelStatus(_ word: String) -> String {
        switch word {
        case "healthy": tr("Tunnel healthy")
        case "degraded": tr("Tunnel degraded")
        case "down": tr("Tunnel down")
        case "inactive": tr("Tunnel inactive")
        default: word
        }
    }

    static func yesNo(_ value: String) -> String {
        switch value {
        case "true": tr("Yes")
        case "false": tr("No")
        default: value
        }
    }

    /// cloudflared's own metrics: redundancy, traffic and version.
    static func cloudflaredFields(_ d: CheckDiagnostic) -> [MonitorCardModel.Field] {
        let f = d.facts
        var out: [MonitorCardModel.Field] = []
        if let ha = f["ha_connections"] { out.append(.init(label: tr("HA connections"), value: ha)) }
        if let expected = d.expected["colos"], let seen = f["connection_colos"] {
            out.append(.init(label: tr("Edge locations"), value: Words.join([colos(seen), colos(seen) == colos(expected) ? "" : tr("Expected \(colos(expected))")])))
        }
        if let total = f["requests_total"] {
            out.append(.init(label: tr("Requests"), value: Words.join([total, f["request_errors"].map { tr("\($0) errors") } ?? ""])))
        }
        if let streams = f["active_streams"] { out.append(.init(label: tr("Active streams"), value: streams)) }
        if let version = f["connector_version"] { out.append(.init(label: tr("Version"), value: version)) }
        return out
    }

    /// The Cloudflare API's account: a tunnel, a DNS record or a pool.
    static func cloudflareFields(_ d: CheckDiagnostic, now: Date) -> [MonitorCardModel.Field] {
        let f = d.facts
        var out: [MonitorCardModel.Field] = []
        if let status = f["tunnel_status"] {
            let word = switch status {
            case "healthy": tr("Healthy")
            case "degraded": tr("Degraded")
            case "down": tr("Down")
            case "inactive": tr("Inactive")
            default: status
            }
            out.append(.init(label: tr("Tunnel"), value: word))
        }
        if let pending = f["tunnel_pending_reconnect"].flatMap(Int.init), pending > 0 {
            out.append(.init(label: tr("Reconnecting"), value: String(pending)))
        }
        if let versions = f["connector_versions"] { out.append(.init(label: tr("Connector versions"), value: versions.replacingOccurrences(of: ",", with: ", "))) }
        if let oldest = f["oldest_connection_at"].flatMap(Timestamp.parse) {
            out.append(.init(label: tr("Oldest connection"), value: tr("opened \(Words.ago(oldest, now: now))")))
        }
        if let proxied = f["record_proxied"] { out.append(.init(label: tr("Proxied"), value: expecting(d, "record_proxied", yesNo(proxied), shown: yesNo))) }
        switch f["record_content_matches"] {
        case "true": out.append(.init(label: tr("Content"), value: tr("Matches")))
        case "false": out.append(.init(label: tr("Content"), value: tr("Differs")))
        default: break
        }
        if let ttl = f["record_ttl"].flatMap(Int.init) { out.append(.init(label: "TTL", value: ttl == 1 ? tr("Auto") : "\(ttl) s")) }
        switch f["pool_healthy"] {
        case "true": out.append(.init(label: tr("Pool"), value: tr("Healthy")))
        case "false": out.append(.init(label: tr("Pool"), value: tr("Unhealthy")))
        default: break
        }
        for key in f.keys.sorted() where key.hasPrefix("origin.") {
            let value = f[key] == "healthy" ? tr("Healthy") : f[key] == "unhealthy" ? tr("Unhealthy") : f[key] ?? ""
            out.append(.init(label: String(key.dropFirst("origin.".count)), value: value, key: key))
        }
        if let regions = f["regions_reporting"] { out.append(.init(label: tr("Regions reporting"), value: regions)) }
        return out
    }

    static func backendState(_ word: String) -> String {
        switch word {
        case "Running": tr("Running")
        case "NeedsLogin": tr("Needs a login")
        case "NeedsMachineAuth": tr("Awaiting device approval")
        case "Stopped": tr("Stopped")
        case "Starting": tr("Starting")
        case "NoState": tr("Not started")
        default: tr("Not recognized")
        }
    }

    /// The local status's hint at the path, which no packet proved.
    static func transportHint(_ word: String, short: Bool = false) -> String {
        switch word {
        case "direct_endpoint_reported": short ? tr("direct endpoint") : tr("Direct endpoint reported")
        case "peer_relay_reported": short ? tr("peer relay") : tr("Peer relay reported")
        case "relay_preference_reported": short ? tr("DERP relay") : tr("DERP relay preferred")
        default: short ? "" : tr("Not reported")
        }
    }

    /// The route a ping measured.
    static func pingRoute(_ word: String) -> String {
        switch word {
        case "direct": tr("direct")
        case "derp": tr("via DERP")
        case "peer_relay": tr("via peer relay")
        default: ""
        }
    }

    /// Tailscale's own status of this observer and the peer, then the
    /// optional ping. Idle is not offline; neither proves the service.
    static func tailscaleFields(_ d: CheckDiagnostic, now: Date) -> [MonitorCardModel.Field] {
        let f = d.facts
        var out: [MonitorCardModel.Field] = []
        if let state = f["backend_state"] { out.append(.init(label: "Tailscale", value: backendState(state))) }
        if let n = f["health_warning_count"].flatMap(Int.init), n > 0 { out.append(.init(label: tr("Health warnings"), value: String(n))) }
        if let online = f["online_reported"] {
            out.append(.init(label: tr("Online"), value: online == "unknown" ? tr("Not reported") : yesNo(online)))
        }
        if let active = f["active_reported"] { out.append(.init(label: tr("Active"), value: active == "false" ? tr("Idle") : yesNo(active))) }
        if let seen = f["last_seen"] {
            // Reported for some peers only, usually offline ones.
            if let at = Timestamp.parse(seen) { out.append(.init(label: tr("Last seen"), value: Words.ago(at, now: now))) }
            else if f["online_reported"] != "true" { out.append(.init(label: tr("Last seen"), value: tr("Not reported"))) }
        }
        if let hint = f["transport_hint"] { out.append(.init(label: tr("Path"), value: transportHint(hint))) }
        if let proto = f["diagnostic_protocol"] {
            let result = switch f["diagnostic_response"] {
            case "received": Words.join([f["diagnostic_latency_ms"].flatMap(Double.init).map(Words.latency) ?? "", pingRoute(f["diagnostic_route"] ?? "")])
            case "timed_out": tr("timed out")
            default: ""
            }
            out.append(.init(label: tr("Ping"), value: Words.join([proto == "tsmp" ? "TSMP" : "Disco", result])))
        }
        return out
    }

    /// `wg show`'s account of the peer. An old handshake alone is not a
    /// tunnel failure.
    static func wireguardFields(_ d: CheckDiagnostic, now: Date) -> [MonitorCardModel.Field] {
        let f = d.facts
        var out: [MonitorCardModel.Field] = []
        if let at = f["last_handshake"].flatMap(Timestamp.parse) { out.append(.init(label: tr("Last handshake"), value: Words.ago(at, now: now))) }
        else if f["rx_bytes"] != nil { out.append(.init(label: tr("Last handshake"), value: tr("None yet"))) }
        if let rx = f["rx_bytes"].flatMap(Double.init) { out.append(.init(label: tr("Received"), value: Words.bytes(rx))) }
        if let tx = f["tx_bytes"].flatMap(Double.init) { out.append(.init(label: tr("Sent"), value: Words.bytes(tx))) }
        if f["sampling_atomicity"] == "separate_command_reads_not_atomic", f["rx_bytes"] != nil {
            out.append(.init(label: tr("Snapshot"), value: tr("Two reads, not atomic")))
        }
        switch f["allowed_ips_match"] {
        case "true": out.append(.init(label: tr("Allowed IPs"), value: tr("Matches")))
        case "false": out.append(.init(label: tr("Allowed IPs"), value: tr("Differs")))
        default: break
        }
        func keepalive(_ v: String) -> String { v == "0" ? tr("Off") : "\(v) s" }
        if let k = f["keepalive_seconds"] { out.append(.init(label: tr("Keepalive"), value: expecting(d, "keepalive_seconds", keepalive(k), shown: keepalive))) }
        else if f["keepalive_match"] == "false" { out.append(.init(label: tr("Keepalive"), value: tr("Differs"))) }
        return out
    }

    /// A trace check's protocol readings, beside its colo, WARP and Gateway.
    static func traceFields(_ d: CheckDiagnostic) -> [MonitorCardModel.Field] {
        [("HTTP", "trace_http"), ("TLS", "trace_tls")].compactMap { label, key in
            d.facts[key].map { .init(label: label, value: $0) }
        }
    }
}

extension SectionBuilder {
    /// `observer` names where every check was read, in place of the
    /// observer `topo` names: "This Mac" for its own checks.
    public static func monitors(_ r: Reading, pins: [MonitorPin], expanded: Set<MonitorPin> = [], observer: String? = nil) -> [ServiceCardModel] {
        var seen = Set<MonitorPin>()
        return pins.prefix(16).compactMap { pin in
            guard seen.insert(pin).inserted, TemplateCompiler.validNode(pin.entity),
                  let row = r.rows.first(where: { $0.row.metric == pin.metric && (pin.kind == .check ? $0.row.select?.check : $0.row.select?.link) == pin.entity }) else { return nil }
            let current = row.isCurrent
            let value = current ? row.value : r.lastValue(of: row)
            var name = pin.entity, subtitle = "", summary = tr("Not known now"), reading = "", provider = ""
            var health = Health.unknown, sampledAt = row.row.sampledAt
            var checks: [CheckCard] = []
            var affected = false
            switch value {
            case .checkCard(let c):
                name = c.check.name; health = c.check.health; sampledAt = c.check.sampledAt
                checks = [c]
                subtitle = Words.join([observer ?? c.observer.name, c.check.kind == "mihomo" ? tr("Core report") : MonitorWords.evidence(c.check.diagnostic?.evidence ?? "")])
                if c.check.kind == "cloudflare" || c.check.kind == "cloudflared" { provider = "Cloudflare" }
                // An HTTP check names the edge that answered it; a trace check is Cloudflare's.
                else if let edge = c.check.diagnostic?.facts["edge_provider"], !edge.isEmpty { provider = Provider.name(edge) }
                else if c.check.diagnostic?.facts.keys.contains(where: { $0.hasPrefix("trace_") }) == true { provider = "Cloudflare" }
                if current { summary = MonitorWords.summary(c.check); reading = MonitorWords.reading(c.check, now: r.now) }
            case .linkCard(let c):
                name = c.summary.name; health = c.summary.health; affected = c.summary.affected
                sampledAt = c.summary.sampledAt; checks = c.checks
                var observers: [String] = []
                for check in c.checks where !observers.contains(check.observer.name) { observers.append(check.observer.name) }
                subtitle = Words.join([observers.isEmpty ? c.summary.transport : observers.prefix(2).joined(separator: " / "), c.summary.transport == "cloudflared" ? tr("Connector report") : MonitorWords.evidence(c.summary.evidence)])
                if c.summary.transport == "cloudflared" { provider = "Cloudflare" }
                if current {
                    switch health {
                    case .up: summary = c.summary.transport == "cloudflared" ? tr("Tunnel established; service unproven") : tr("Link available")
                    case .down: summary = tr("Link unavailable")
                    case .degraded: summary = tr("Link degraded")
                    case .unknown: summary = tr("Link availability unproven")
                    }
                    // The connector's reading precedes the API's account of the same tunnel.
                    let primary = checks.first { $0.check.kind == "cloudflared" } ?? checks.first
                    reading = primary.map { MonitorWords.reading($0.check, now: r.now) } ?? ""
                }
            default: break
            }
            let missing = row.row.reason == "entity_missing"
            if missing { summary = tr("Not in this view") }
            let details = checks.map { c -> MonitorCardModel.Check in
                let k = current ? c.check : c.check.withheld()
                let history: ServiceCardModel.History
                if k.freshness != "fresh" { history = .withheld }
                else if let slots = k.samples?.slots {
                    history = .samples(slots.map { s in
                        switch s.outcome {
                        case .ok: s.elapsed.map { .ok($0) } ?? .unknown
                        case .fail: .fail
                        case .policy: .policy
                        case .error: .error
                        case .unknown: .unknown
                        case .none: .none
                        }
                    })
                } else { history = .none }
                return .init(id: k.id, name: k.name, source: Words.join([observer ?? c.observer.name, MonitorWords.evidence(k.diagnostic?.evidence ?? "")]),
                             mark: current ? Mark(k.health) : .offline, summary: MonitorWords.summary(k), reading: MonitorWords.reading(k, now: r.now),
                             code: k.diagnostic?.code.isEmpty == false ? Words.join([k.diagnostic?.stage ?? "", k.diagnostic?.code ?? ""]) : "", history: history,
                             p50: k.latency?.p50, p50Label: k.diagnostic?.evidence == "reported" ? tr("Read p50") : "p50", fields: MonitorWords.fields(k, now: r.now), up24h: k.up24h)
            }
            let mark: Mark = missing ? .unknown : !current ? .offline : affected && health == .up ? .degraded : Mark(health)
            let pill: Pill = missing ? .health(.unknown) : !current ? .cached
                : affected ? Pill(text: Pill.state("affected", health: health).text, mark: mark) : .health(health)
            var card = ServiceCardModel(id: pin.entity, name: name, application: "", host: .init(name: "", kind: pin.kind == .link ? "edge" : "", provider: provider),
                                       hostMark: .unknown, mark: mark, pill: pill, isWithheld: !current,
                                       isMissing: missing, observers: [], checks: [], sampledAt: sampledAt, now: r.now)
            card.monitor = .init(pin: pin, subtitle: subtitle, summary: summary, reading: reading, checks: details, expanded: expanded.contains(pin))
            return card
        }
    }
}
