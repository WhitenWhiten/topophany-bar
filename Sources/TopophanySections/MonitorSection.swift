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
        case "certificate_expiring": return tr("Certificate expires soon")
        case "latency_exceeded": return tr("Slower than its latency budget")
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
            return d.evidence == "reported" ? tr("Reported check passing") : tr("Check passing")
        default: return tr("Evidence incomplete")
        }
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
        default: break
        }
        return out
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

    /// At most two relevant readings; missing values are never interpreted as zero.
    public static func reading(_ c: ServiceCard.Check) -> String {
        guard let d = c.diagnostic else { return "" }
        let f = d.facts
        if c.kind == "mihomo" {
            if let chain = f["reported_chain"], !chain.isEmpty { return tr("Reported route: \(chain.replacingOccurrences(of: " -> ", with: " → ").replacingOccurrences(of: "withheld_secret_request", with: tr("withheld")))") }
            let tun = f["tun_enabled"].map { $0 == "true" ? tr("TUN on") : $0 == "false" ? tr("TUN off") : "" } ?? ""
            return Words.join([f["mode"] ?? "", tun])
        }
        if let n = f["ready_connections"] ?? f["tunnel_connections"] {
            let count = d.expected["connections"].map { n + "/" + $0 } ?? n
            return Words.join([tr("\(count) connections"), f["connection_colos"] ?? f["tunnel_colos"] ?? ""])
        }
        if let n = f["origins_healthy"], let total = f["origins_total"] { return tr("\(n)/\(total) origins healthy") }
        if let n = f["record_count"] { return tr("\(n) DNS records") }
        return Words.join([f["edge_pop"] ?? "", f["edge_cache"] ?? ""])
    }
}

extension SectionBuilder {
    public static func monitors(_ r: Reading, pins: [MonitorPin], expanded: Set<MonitorPin> = []) -> [ServiceCardModel] {
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
                subtitle = Words.join([c.observer.name, c.check.kind == "mihomo" ? tr("Core report") : MonitorWords.evidence(c.check.diagnostic?.evidence ?? "")])
                if c.check.kind == "cloudflare" || c.check.kind == "cloudflared" { provider = "Cloudflare" }
                if current { summary = MonitorWords.summary(c.check); reading = MonitorWords.reading(c.check) }
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
                    reading = primary.map { MonitorWords.reading($0.check) } ?? ""
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
                return .init(id: k.id, name: k.name, source: Words.join([c.observer.name, MonitorWords.evidence(k.diagnostic?.evidence ?? "")]),
                             mark: current ? Mark(k.health) : .offline, summary: MonitorWords.summary(k), reading: MonitorWords.reading(k),
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
