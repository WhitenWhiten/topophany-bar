import Foundation
import TopophanyKit

/// Compact checks and links share the existing pinned-card surface. Detailed
/// evidence is prepared here once per data update, never inside drawing code.
public struct MonitorCardModel: Sendable, Hashable {
    public struct Field: Sendable, Hashable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }
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

    public static func summary(_ c: ServiceCard.Check) -> String {
        guard let d = c.diagnostic else { return tr("Not known now") }
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

    public static func fields(_ c: ServiceCard.Check) -> [MonitorCardModel.Field] {
        guard let d = c.diagnostic else { return [] }
        var out: [MonitorCardModel.Field] = policyField(d).map { [$0] } ?? []
        guard c.kind == "mihomo" else { return out }
        for (key, label) in [("mode", tr("Mode")), ("tun_enabled", "TUN"), ("provider_comparison", tr("Providers")), ("core_delay_ms", tr("Core last delay"))] {
            guard let value = d.facts[key], !value.isEmpty else { continue }
            var text = key == "core_delay_ms" ? value + " ms" : value
            if let expected = d.expected[key], expected != value { text = Words.join([text, tr("Expected \(expected)")]) }
            out.append(.init(label: label, value: text))
        }
        return out
    }

    /// At most two relevant readings; missing values are never interpreted as zero.
    public static func reading(_ c: ServiceCard.Check) -> String {
        guard let d = c.diagnostic else { return "" }
        let f = d.facts
        if c.kind == "mihomo" {
            if let chain = f["reported_chain"], !chain.isEmpty { return tr("Reported route: \(chain.replacingOccurrences(of: " -> ", with: " → ").replacingOccurrences(of: "withheld_secret_request", with: tr("withheld")))") }
            return Words.join([f["mode"] ?? "", f["tun_enabled"].map { "TUN " + $0 } ?? ""])
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
                             p50: k.latency?.p50, p50Label: k.diagnostic?.evidence == "reported" ? tr("Read p50") : "p50", fields: MonitorWords.fields(k), up24h: k.up24h)
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
