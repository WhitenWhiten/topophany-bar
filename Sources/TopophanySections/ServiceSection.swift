import Foundation
import TopophanyKit

/// A service's card, as the Services tab draws it: the observers that see
/// it, how fast it answered them lately and how much of the day it was up,
/// in place of a server's CPU, memory and disk.
public struct ServiceCardModel: Sendable, Hashable, Identifiable {
    /// One interval of a check's history, as `topo` laid it out.
    public enum Sample: Sendable, Hashable {
        /// Passed, in this many milliseconds.
        case ok(Double)
        case fail
        /// Answered, against the check's policy.
        case policy
        case error
        case unknown
        /// No sample was taken in that interval.
        case none
    }

    /// A check's recent samples as far as they can be drawn.
    public enum History: Sendable, Hashable {
        /// Oldest first.
        case samples([Sample])
        /// `topo` holds none for the check yet: nothing is drawn.
        case none
        /// Past the check's deadline, or nothing current: drawn hatched.
        case withheld
    }

    /// One observer's row: a mark per check, and its worst check's readings.
    public struct Observer: Sendable, Hashable, Identifiable {
        public var id: String
        /// Its place, or its name where two observers share one.
        public var label: String
        /// One per check, worst first.
        public var marks: [Mark]
        /// The worst check's recent samples.
        public var history: History
        /// The worst check's median over the day, in ms; `nil` when unknown.
        public var p50: Double?
        /// The worst check's share of the day up; `nil` when unknown.
        public var up24h: Double?

        public init(id: String, label: String, marks: [Mark], history: History, p50: Double?, up24h: Double?) {
            self.id = id
            self.label = label
            self.marks = marks
            self.history = history
            self.p50 = p50
            self.up24h = up24h
        }
    }

    /// An edge or a proxy in front, or the node it runs on.
    public struct Node: Sendable, Hashable {
        public var name: String
        public var kind: String
        public var provider: String

        public init(name: String, kind: String, provider: String) {
            self.name = name
            self.kind = kind
            self.provider = provider
        }
    }

    /// How it is reached.
    public struct Endpoint: Sendable, Hashable {
        public var network: String
        public var address: String
        /// `nil` where no check targets the address.
        public var mark: Mark?
        /// The first edge or proxy in front.
        public var via: Node?

        public init(network: String, address: String, mark: Mark?, via: Node?) {
            self.network = network
            self.address = address
            self.mark = mark
            self.via = via
        }

        /// The address without its scheme and path: "www.example.com".
        public var host: String {
            var s = Substring(address)
            if let r = s.range(of: "://") { s = s[r.upperBound...] }
            if let slash = s.firstIndex(of: "/") { s = s[..<slash] }
            return String(s)
        }
    }

    /// A service it depends on.
    public struct Related: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var mark: Mark

        public init(id: String, name: String, mark: Mark) {
            self.id = id
            self.name = name
            self.mark = mark
        }
    }

    public var id: String
    public var name: String
    /// Its application's name; empty for none.
    public var application: String
    /// Where it runs: the node, as the server cards' tile takes it.
    public var host: Node
    public var hostPlace: String
    public var hostMark: Mark
    /// Beside its name: its state, AFFECTED reading as a warning.
    public var mark: Mark
    public var pill: Pill
    /// Past its deadline, or nothing current: values withheld.
    public var isWithheld: Bool
    /// The service isn't in the topology.
    public var isMissing: Bool
    /// No check measures it.
    public var isUnmonitored: Bool
    /// No check of the observer the view is scoped to measures it; other
    /// observers' do.
    public var isElsewhere: Bool
    /// Nothing of it was ever received: its ID alone.
    public var isBlank: Bool
    public var observers: [Observer]
    /// Every check's mark, worst first.
    public var checks: [Mark]
    public var endpoints: [Endpoint]
    /// What stands in front: the first edge an endpoint names, or the edge
    /// or platform it runs on.
    public var edge: Node?
    /// The colos the edge named in the checks' newest responses.
    public var colos: [String]
    public var dependsOn: [Related]
    public var usedBy: Int
    /// `topo`'s words for its state, for VoiceOver.
    public var reason: String
    /// Where its card is missing, why, in place of where it runs.
    public var placeholder: String
    /// The newest check's sample.
    public var sampledAt: Date?
    public var now: Date

    public init(id: String, name: String, application: String, host: Node, hostPlace: String = "", hostMark: Mark,
                mark: Mark, pill: Pill, isWithheld: Bool, isMissing: Bool = false, isUnmonitored: Bool = false, isElsewhere: Bool = false, isBlank: Bool = false,
                observers: [Observer], checks: [Mark], endpoints: [Endpoint] = [], edge: Node? = nil, colos: [String] = [],
                dependsOn: [Related] = [], usedBy: Int = 0, reason: String = "", placeholder: String = "", sampledAt: Date?,
                now: Date) {
        self.id = id
        self.name = name
        self.application = application
        self.host = host
        self.hostPlace = hostPlace
        self.hostMark = hostMark
        self.mark = mark
        self.pill = pill
        self.isWithheld = isWithheld
        self.isMissing = isMissing
        self.isUnmonitored = isUnmonitored
        self.isElsewhere = isUnmonitored && isElsewhere
        self.isBlank = isBlank || isMissing
        self.observers = observers
        self.checks = checks
        self.endpoints = endpoints
        self.edge = edge
        self.colos = colos
        self.dependsOn = dependsOn
        self.usedBy = usedBy
        self.reason = reason
        self.placeholder = placeholder
        self.sampledAt = sampledAt
        self.now = now
    }

    /// "on BandwagonHost LA".
    public var onHost: String { host.name.isEmpty ? "" : tr("on \(host.name)") }

    /// "Proxy chain · on BandwagonHost LA".
    public var subtitle: String {
        guard !isMissing else { return placeholder.isEmpty ? tr("Not in the topology") : placeholder }
        return Words.join([application, onHost])
    }

    /// What a card with no observer to show says: "Not monitored", "Not
    /// seen from here" or "Not known now", and why, in its own case.
    public var quiet: (title: String, why: String) {
        if isElsewhere { return (tr("Not seen from here"), tr("others check it")) }
        if isUnmonitored { return (tr("Not monitored"), tr("no check measures it")) }
        return (tr("Not known now"), "")
    }

    /// "4 checks · 2 failing", "3 checks · all passing", "not monitored".
    public var checksText: String {
        guard !isBlank else { return "" }
        guard !checks.isEmpty else { return isElsewhere ? tr("not seen from here") : isUnmonitored ? tr("not monitored") : tr("no checks") }
        let n = tr("\(checks.count) checks")
        if isWithheld { return Words.join([n, tr("not known now")]) }
        let down = checks.count { $0 == .down }
        let warn = checks.count { $0 == .degraded }
        let unknown = checks.count { $0 == .unknown || $0 == .offline }
        if down > 0 { return Words.join([n, tr("\(down) failing")]) }
        if warn > 0 { return Words.join([n, tr("\(warn) warn")]) }
        if unknown > 0 { return Words.join([n, tr("\(unknown) unknown")]) }
        return Words.join([n, tr("all passing")])
    }

    /// The endpoint it is known by in public, or its first.
    public var knownAt: Endpoint? { endpoints.first { $0.network == "public" } ?? endpoints.first }

    /// "4s ago", or "last reading 3 min ago" when withheld.
    public var age: String {
        guard let sampledAt else { return isBlank || isUnmonitored ? "" : tr("no reading") }
        let a = Words.ago(sampledAt, now: now)
        return isWithheld ? tr("last reading \(a)") : a
    }

    /// The age in a widget's room: "4s", "last 3m".
    public var shortAge: String {
        guard let sampledAt else { return "" }
        let s = Words.span(since: sampledAt, now: now, style: .compact)
        return isWithheld ? tr("last \(s)") : s
    }

    /// Everything as history at `date`: names stay, every health and
    /// reading is withheld.
    public func withheld(at date: Date) -> ServiceCardModel {
        var c = self
        c.now = date
        guard !isMissing else { return c }
        c.isWithheld = true
        c.mark = .offline
        c.pill = .cached
        c.hostMark = .offline
        c.observers = observers.map {
            Observer(id: $0.id, label: $0.label, marks: $0.marks.map { _ in .offline }, history: .withheld, p50: nil, up24h: nil)
        }
        c.checks = checks.map { _ in .offline }
        c.endpoints = endpoints.map { Endpoint(network: $0.network, address: $0.address, mark: .offline, via: $0.via) }
        c.colos = []
        c.dependsOn = dependsOn.map { Related(id: $0.id, name: $0.name, mark: .offline) }
        return c
    }
}

extension SectionBuilder {
    // MARK: services

    /// The cards of `ids`, in order: those pinned, or a Service widget's.
    public static func services(_ r: Reading, ids: [String]) -> [ServiceCardModel] {
        var out: [ServiceCardModel] = []
        var seen = Set<String>()
        for id in ids where TemplateCompiler.validNode(id) && seen.insert(id).inserted {
            let row = r.rows.first { $0.row.metric == "service.card" && $0.row.select?.service == id }
            if let c = service(row, id: id, reading: r) { out.append(c) }
        }
        return out
    }

    static func service(_ row: RowReading?, id: String, reading r: Reading) -> ServiceCardModel? {
        guard let row else { return nil }
        let now = r.now
        if case .serviceCard(let c) = row.value { return service(c, withheld: false, now: now) }
        if case .serviceCard(let c) = r.lastValue(of: row) { return service(c, withheld: true, now: now) }
        let missing = row.row.reason == "entity_missing"
        return ServiceCardModel(id: id, name: id, application: "", host: .init(name: "", kind: "", provider: ""),
                                hostMark: missing ? .unknown : .offline, mark: missing ? .unknown : .offline,
                                pill: missing ? Pill.health(.unknown) : .cached, isWithheld: !missing, isMissing: missing,
                                isBlank: true, observers: [], checks: [], sampledAt: nil, now: now)
    }

    static func service(_ c: ServiceCard, withheld: Bool, now: Date) -> ServiceCardModel {
        func sample(_ s: ServiceCard.Slot) -> ServiceCardModel.Sample {
            switch s.outcome {
            case .ok: s.elapsed.map { .ok($0) } ?? .unknown
            case .fail: .fail
            case .policy: .policy
            case .error: .error
            case .unknown: .unknown
            case .none: .none
            }
        }
        let observers = c.seenFrom.map { o -> ServiceCardModel.Observer in
            let worst = o.checks.first
            let fresh = worst?.freshness == "fresh"
            // No samples held yet draws nothing; none past the check's
            // deadline, or in a view that isn't fresh, is withheld.
            let history: ServiceCardModel.History = if let slots = worst?.samples?.slots { .samples(slots.map(sample)) }
                else if fresh { .none } else { .withheld }
            return .init(id: o.observer.id, label: o.label.isEmpty ? o.observer.name : o.label,
                         marks: o.checks.map { Mark($0.health) }, history: history,
                         p50: fresh ? worst?.latency?.p50 : nil, up24h: worst?.up24h)
        }
        let checks = c.seenFrom.flatMap(\.checks)
        let host = ServiceCardModel.Node(name: c.host?.name ?? "", kind: c.host?.kind ?? "", provider: Provider.name(c.host?.provider ?? ""))
        let edge: ServiceCardModel.Node? = c.endpoints.lazy.compactMap(\.via.first).first.map {
            .init(name: $0.name, kind: $0.kind, provider: Provider.name($0.provider))
        } ?? (host.kind == "edge" || host.kind == "platform" ? host : nil)
        var colos: [String] = []
        for k in checks { if let colo = k.colo, !colos.contains(colo) { colos.append(colo) } }
        let mark: Mark = c.note == "cached" ? .offline : c.note == "affected" && c.health == .up ? .degraded : Mark(c.health)
        let pill = c.note.isEmpty ? Pill.health(c.health) : c.note == "cached" ? .cached : Pill.state(c.note, health: c.health)
        let card = ServiceCardModel(
            id: c.id, name: c.name, application: c.application?.name ?? "", host: host, hostPlace: c.host?.place ?? "",
            hostMark: Mark(c.host?.health ?? .unknown), mark: mark, pill: pill, isWithheld: false,
            isUnmonitored: c.monitored == false, isElsewhere: c.elsewhere, observers: observers,
            checks: Mark.troubleFirst(checks.map { Mark($0.health) }) { $0 },
            endpoints: c.endpoints.map { e in
                .init(network: e.network, address: e.address, mark: e.health.map { Mark($0) },
                      via: e.via.first.map { .init(name: $0.name, kind: $0.kind, provider: Provider.name($0.provider)) })
            },
            edge: edge, colos: colos,
            dependsOn: c.dependsOn.map { d in
                .init(id: d.id, name: d.name, mark: d.affected == true && d.health == .up ? .degraded : Mark(d.health))
            },
            usedBy: c.usedBy.count, reason: c.reason, sampledAt: checks.compactMap(\.sampledAt).max(), now: now)
        return withheld ? card.withheld(at: now) : card
    }
}
