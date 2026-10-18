import Foundation

// Row values of the metrics the panel draws (PROTOCOL.md §3.3). Every field
// that may be unknown is optional; nothing defaults to zero. Fields the app
// doesn't know are ignored.

/// `view.Verdict().State`. Unknown states are kept by name and drawn as
/// unknown.
public enum VerdictState: Sendable, Hashable {
    case clear, degraded, incidents, down, incomplete, noEvidence, noChecks, cached
    case other(String)

    public init(_ raw: String) {
        switch raw {
        case "clear": self = .clear
        case "degraded": self = .degraded
        case "incidents": self = .incidents
        case "down": self = .down
        case "incomplete": self = .incomplete
        case "no-evidence": self = .noEvidence
        case "no-checks": self = .noChecks
        case "cached": self = .cached
        default: self = .other(raw)
        }
    }

    public var rawValue: String {
        switch self {
        case .clear: "clear"
        case .degraded: "degraded"
        case .incidents: "incidents"
        case .down: "down"
        case .incomplete: "incomplete"
        case .noEvidence: "no-evidence"
        case .noChecks: "no-checks"
        case .cached: "cached"
        case .other(let s): s
        }
    }
}

/// Checks by health for `summary.verdict`. `paused` and `maintenance` are
/// subsets of `unknown`, never added to the total; `configured` is
/// up + warning + down + unknown as `topo` sent it.
public struct VerdictCounts: Sendable, Hashable {
    public var health: HealthCounts
    public var paused: Int?
    public var maintenance: Int?

    public init(health: HealthCounts, paused: Int? = nil, maintenance: Int? = nil) {
        self.health = health
        self.paused = paused
        self.maintenance = maintenance
    }
}

public struct ObserversLive: Sendable, Hashable, Decodable {
    public var live: Int?
    public var all: Int?

    public init(live: Int?, all: Int?) {
        self.live = live
        self.all = all
    }
}

/// `summary.verdict`.
public struct Verdict: Sendable, Hashable, Decodable {
    public var state: VerdictState
    public var glyph: String
    public var text: String
    public var counts: VerdictCounts?
    public var configured: Int?
    public var incidents: Int?
    public var observers: ObserversLive?

    enum CodingKeys: String, CodingKey { case state, glyph, text, counts, configured, incidents, observers }
    enum CountKeys: String, CodingKey { case up, warning, down, unknown, paused, maintenance }

    public init(state: VerdictState, glyph: String, text: String, counts: VerdictCounts?, configured: Int?,
                incidents: Int?, observers: ObserversLive?) {
        self.state = state
        self.glyph = glyph
        self.text = text
        self.counts = counts
        self.configured = configured
        self.incidents = incidents
        self.observers = observers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = VerdictState(try c.decode(String.self, forKey: .state))
        glyph = (try? c.decodeIfPresent(String.self, forKey: .glyph)) ?? ""
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        if let n = try? c.nestedContainer(keyedBy: CountKeys.self, forKey: .counts) {
            counts = VerdictCounts(
                health: HealthCounts(up: n.count(.up), warning: n.count(.warning), down: n.count(.down), unknown: n.count(.unknown)),
                paused: n.count(.paused), maintenance: n.count(.maintenance))
        }
        configured = c.count(.configured)
        incidents = c.count(.incidents)
        observers = try? c.decodeIfPresent(ObserversLive.self, forKey: .observers)
    }
}

/// One entry of `observers.verdicts`, and of a server card's `observes`.
public struct ObserverVerdict: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var node: String
    public var health: Health
    public var state: VerdictState?
    public var live: Bool?
    public var lastSeen: Date?
    public var counts: HealthCounts?
    /// The deadline of the checks and heartbeat behind this verdict, where
    /// `topo` states one (a server card's `observes`).
    public var validUntil: Date?

    enum CodingKeys: String, CodingKey { case id, name, node, health, state, live, lastSeen = "last_seen", counts, validUntil = "valid_until" }

    public init(id: String, name: String, node: String = "", health: Health, state: VerdictState?, live: Bool?,
                lastSeen: Date?, counts: HealthCounts?) {
        self.id = id
        self.name = name
        self.node = node
        self.health = health
        self.state = state
        self.live = live
        self.lastSeen = lastSeen
        self.counts = counts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.text(.name) ?? id
        node = c.text(.node) ?? ""
        health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        state = c.text(.state).map(VerdictState.init)
        live = try? c.decodeIfPresent(Bool.self, forKey: .live)
        lastSeen = c.timestamp(.lastSeen)
        counts = try? c.decodeIfPresent(HealthCounts.self, forKey: .counts)
        validUntil = c.timestamp(.validUntil)
    }
}

/// `attention.list`.
public struct AttentionList: Sendable, Hashable, Decodable {
    public var total: Int?
    public var items: [AttentionItem]

    enum CodingKeys: String, CodingKey { case total, items }

    public init(total: Int?, items: [AttentionItem]) {
        self.total = total
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.count(.total)
        items = try c.decodeIfPresent([AttentionItem].self, forKey: .items) ?? []
    }
}

public struct AttentionItem: Sendable, Hashable, Decodable, Identifiable {
    public var kind: String
    public var id: String
    public var title: String
    public var route: [String]
    public var observer: String
    public var observerName: String
    public var since: Date?
    public var health: Health
    /// The TUI's state word, lowercased. Any word is accepted; one the
    /// renderer doesn't know is drawn by `health`.
    public var state: String

    enum CodingKeys: String, CodingKey {
        case kind, id, title, route, observer, observerName = "observer_name", since, health, state
    }

    public init(kind: String, id: String, title: String, route: [String], observer: String, observerName: String,
                since: Date?, health: Health, state: String) {
        self.kind = kind
        self.id = id
        self.title = title
        self.route = route
        self.observer = observer
        self.observerName = observerName
        self.since = since
        self.health = health
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.text(.kind) ?? ""
        id = c.text(.id) ?? ""
        title = c.text(.title) ?? ""
        route = (try? c.decodeIfPresent([String].self, forKey: .route)) ?? []
        if route.isEmpty, !title.isEmpty { route = [title] }
        observer = c.text(.observer) ?? ""
        observerName = c.text(.observerName) ?? ""
        since = c.timestamp(.since)
        health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        state = (c.text(.state) ?? "").lowercased()
    }
}

/// A service as the Services tab and the server card list it.
public struct ServiceEntry: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var health: Health
    public var monitored: Bool?
    public var affected: Bool?

    enum CodingKeys: String, CodingKey { case id, name, health, monitored, affected }

    public init(id: String, name: String, health: Health, monitored: Bool?, affected: Bool?) {
        self.id = id
        self.name = name
        self.health = health
        self.monitored = monitored
        self.affected = affected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.text(.id) ?? ""
        name = c.text(.name) ?? id
        health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        monitored = try? c.decodeIfPresent(Bool.self, forKey: .monitored)
        affected = try? c.decodeIfPresent(Bool.self, forKey: .affected)
    }
}

/// One entry of `applications.list`.
public struct Application: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var environment: String
    public var health: Health
    public var services: [ServiceEntry]
    public var counts: HealthCounts?
    public var attention: Int?
    public var unmonitored: Int?

    enum CodingKeys: String, CodingKey { case id, name, environment, health, services, counts, attention, unmonitored }

    public init(id: String, name: String, environment: String = "", health: Health, services: [ServiceEntry],
                counts: HealthCounts?, attention: Int?, unmonitored: Int?) {
        self.id = id
        self.name = name
        self.environment = environment
        self.health = health
        self.services = services
        self.counts = counts
        self.attention = attention
        self.unmonitored = unmonitored
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.text(.name) ?? id
        environment = c.text(.environment) ?? ""
        health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        services = try c.decodeIfPresent([ServiceEntry].self, forKey: .services) ?? []
        counts = try? c.decodeIfPresent(HealthCounts.self, forKey: .counts)
        attention = c.count(.attention)
        unmonitored = c.count(.unmonitored)
    }
}

/// `server.card`.
public struct ServerCard: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var provider: String
    public var group: String
    public var place: String
    public var health: Health
    /// `affected`, `outdated` or empty.
    public var note: String
    public var resources: [Resource]
    public var services: [ServiceEntry]
    public var observes: [ObserverVerdict]

    enum CodingKeys: String, CodingKey {
        case id, name, kind, provider, group, place = "where", health, note, resources, services, observes
    }

    public init(id: String, name: String, kind: String, provider: String, group: String = "", place: String,
                health: Health, note: String, resources: [Resource], services: [ServiceEntry], observes: [ObserverVerdict]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.provider = provider
        self.group = group
        self.place = place
        self.health = health
        self.note = note
        self.resources = resources
        self.services = services
        self.observes = observes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.text(.name) ?? id
        kind = c.text(.kind) ?? ""
        provider = c.text(.provider) ?? ""
        group = c.text(.group) ?? ""
        place = c.text(.place) ?? ""
        health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        note = c.text(.note) ?? ""
        resources = try c.decodeIfPresent([Resource].self, forKey: .resources) ?? []
        services = try c.decodeIfPresent([ServiceEntry].self, forKey: .services) ?? []
        observes = try c.decodeIfPresent([ObserverVerdict].self, forKey: .observes) ?? []
    }

    /// One host check's readings on the node. Numbers are `nil` unless the
    /// check is fresh; a `nil` limit means the check sets none.
    public struct Resource: Sendable, Hashable, Decodable {
        public var check: String
        public var observer: String
        public var health: Health
        public var freshness: String
        public var sampledAt: Date?
        public var validUntil: Date?
        public var cpu: CPU?
        public var memory: Memory?
        public var disk: Disk?
        public var process: ProcessMatch?

        enum CodingKeys: String, CodingKey {
            case check, observer, health, freshness, sampledAt = "sampled_at", validUntil = "valid_until"
            case cpu, memory, disk, process
        }

        public init(check: String, observer: String, health: Health, freshness: String, sampledAt: Date?,
                    validUntil: Date?, cpu: CPU?, memory: Memory?, disk: Disk?, process: ProcessMatch?) {
            self.check = check
            self.observer = observer
            self.health = health
            self.freshness = freshness
            self.sampledAt = sampledAt
            self.validUntil = validUntil
            self.cpu = cpu
            self.memory = memory
            self.disk = disk
            self.process = process
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            check = c.text(.check) ?? ""
            observer = c.text(.observer) ?? ""
            health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
            freshness = c.text(.freshness) ?? ""
            sampledAt = c.timestamp(.sampledAt)
            validUntil = c.timestamp(.validUntil)
            cpu = try? c.decodeIfPresent(CPU.self, forKey: .cpu)
            memory = try? c.decodeIfPresent(Memory.self, forKey: .memory)
            disk = try? c.decodeIfPresent(Disk.self, forKey: .disk)
            process = try? c.decodeIfPresent(ProcessMatch.self, forKey: .process)
        }
    }

    public struct CPU: Sendable, Hashable, Decodable {
        public var percent: Double?
        public var limit: Double?
        public var logical: Int?

        public init(percent: Double?, limit: Double?, logical: Int?) {
            self.percent = percent
            self.limit = limit
            self.logical = logical
        }
    }

    public struct Memory: Sendable, Hashable, Decodable {
        public var percent: Double?
        public var limit: Double?
        public var usedBytes: Int64?
        public var totalBytes: Int64?
        public var basis: String?

        enum CodingKeys: String, CodingKey { case percent, limit, usedBytes = "used_bytes", totalBytes = "total_bytes", basis }

        public init(percent: Double?, limit: Double?, usedBytes: Int64?, totalBytes: Int64?, basis: String? = nil) {
            self.percent = percent
            self.limit = limit
            self.usedBytes = usedBytes
            self.totalBytes = totalBytes
            self.basis = basis
        }
    }

    public struct Disk: Sendable, Hashable, Decodable {
        public var percent: Double?
        public var limit: Double?
        public var path: String?
        public var usedBytes: Int64?
        public var totalBytes: Int64?

        enum CodingKeys: String, CodingKey { case percent, limit, path, usedBytes = "used_bytes", totalBytes = "total_bytes" }

        public init(percent: Double?, limit: Double?, path: String?, usedBytes: Int64?, totalBytes: Int64?) {
            self.percent = percent
            self.limit = limit
            self.path = path
            self.usedBytes = usedBytes
            self.totalBytes = totalBytes
        }
    }

    public struct ProcessMatch: Sendable, Hashable, Decodable {
        public var name: String
        public var matching: Int?

        public init(name: String, matching: Int?) {
            self.name = name
            self.matching = matching
        }
    }
}

extension ServerCard {
    /// The card with each resource's and nested observer's own deadline
    /// applied at `now` (PROTOCOL.md §3.3): past it, a resource keeps its
    /// identity and times but none of its numbers, and an observer keeps its
    /// identity and `last_seen` with everything it counted moved to unknown.
    /// A nested deadline never expires the whole card.
    public func applyingDeadlines(at now: Date, tolerance: TimeInterval) -> ServerCard {
        var c = self
        let horizon = now.addingTimeInterval(tolerance)
        func lapsed(_ d: Date?) -> Bool { d.map { now >= $0 || $0 > horizon } ?? false }
        c.resources = resources.map { r in
            guard lapsed(r.validUntil) || (r.sampledAt.map { $0 > horizon } ?? false) else { return r }
            var x = r
            x.health = .unknown
            if x.freshness == "fresh" { x.freshness = "stale" }
            x.cpu = r.cpu.map { _ in CPU(percent: nil, limit: nil, logical: nil) }
            x.memory = r.memory.map { m in Memory(percent: nil, limit: nil, usedBytes: nil, totalBytes: nil, basis: m.basis) }
            x.disk = r.disk.map { d in Disk(percent: nil, limit: nil, path: d.path, usedBytes: nil, totalBytes: nil) }
            x.process = r.process.map { ProcessMatch(name: $0.name, matching: nil) }
            return x
        }
        c.observes = observes.map { o in
            guard lapsed(o.validUntil) else { return o }
            var x = o
            x.state = .cached
            x.health = .unknown
            x.live = false
            if let k = o.counts {
                let all = (k.up ?? 0) + (k.warning ?? 0) + (k.down ?? 0) + (k.unknown ?? 0)
                x.counts = HealthCounts(up: 0, warning: 0, down: 0, unknown: all)
            }
            return x
        }
        return c
    }
}

extension KeyedDecodingContainer {
    func text(_ key: Key) -> String? {
        (try? decodeIfPresent(String.self, forKey: key)) ?? nil
    }

    /// A count: an integer ≥ 0, or `nil` when absent, null or invalid.
    func count(_ key: Key) -> Int? {
        guard let n = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil, n >= 0 else { return nil }
        return n
    }
}
