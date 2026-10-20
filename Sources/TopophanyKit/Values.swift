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
/// A node with a card in the Servers tab, for choosing nodes (`servers.list`).
public struct ServerListEntry: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var provider: String
    public var group: String
    public var place: String
    public var health: Health
    public var note: String

    enum CodingKeys: String, CodingKey { case id, name, kind, provider, group, place = "where", health, note }

    public init(id: String, name: String, kind: String = "", provider: String = "", group: String = "", place: String = "",
                health: Health = .unknown, note: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.provider = provider
        self.group = group
        self.place = place
        self.health = health
        self.note = note
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
    }

    /// The node whose ID or name matches a Mac's `LocalHostName`, ignoring
    /// case and punctuation: what Settings suggests for This Mac.
    public static func matching(localHostName host: String, in list: [ServerListEntry]) -> ServerListEntry? {
        func slug(_ s: String) -> String { s.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-") }
        let h = slug(host)
        guard !h.isEmpty else { return nil }
        return list.first { slug($0.id) == h || slug($0.name) == h }
    }
}

/// `topo monitor stream --profiles`: saved client profiles, by name and
/// project; never a token.
public struct ProfileList: Sendable, Hashable, Decodable {
    public struct Profile: Sendable, Hashable, Decodable, Identifiable {
        public var name: String
        public var project: String
        public var active: Bool

        public var id: String { name }

        enum CodingKeys: String, CodingKey { case name, project, active }

        public init(name: String, project: String = "", active: Bool = false) {
            self.name = name
            self.project = project
            self.active = active
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            project = c.text(.project) ?? ""
            active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? false
        }
    }

    public var profiles: [Profile]

    public init(profiles: [Profile]) { self.profiles = profiles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = (try? c.decodeIfPresent([Profile].self, forKey: .profiles)) ?? []
    }

    enum CodingKeys: String, CodingKey { case profiles }

    /// The profile a request's empty `profile` selects.
    public var active: Profile? { profiles.first { $0.active } }
}

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

/// `service.card`: a service's card, as the Services tab draws it. The
/// app adds nothing to it: what it says is `topo`'s.
public struct ServiceCard: Sendable, Hashable, Decodable, Identifiable {
    /// An entity by ID and name: the application, an observer.
    public struct Ref: Sendable, Hashable, Decodable {
        public var id: String
        public var name: String

        enum CodingKeys: String, CodingKey { case id, name }

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id) ?? ""
            name = c.text(.name) ?? id
        }
    }

    /// The node the service runs on, with that node's state.
    public struct Host: Sendable, Hashable, Decodable {
        public var id: String
        public var name: String
        public var kind: String
        public var provider: String
        public var place: String
        public var health: Health

        enum CodingKeys: String, CodingKey { case id, name, kind, provider, place = "where", health }

        public init(id: String, name: String, kind: String = "", provider: String = "", place: String = "",
                    health: Health = .unknown) {
            self.id = id
            self.name = name
            self.kind = kind
            self.provider = provider
            self.place = place
            self.health = health
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id) ?? ""
            name = c.text(.name) ?? id
            kind = c.text(.kind) ?? ""
            provider = c.text(.provider) ?? ""
            place = c.text(.place) ?? ""
            health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        }
    }

    /// One observer's view of the service: its checks, worst first.
    public struct SeenFrom: Sendable, Hashable, Decodable {
        public var observer: Ref
        /// Its place, or its name where two observers share one; for
        /// display only.
        public var label: String
        public var health: Health
        public var checks: [Check]

        enum CodingKeys: String, CodingKey { case observer, label, health, checks }

        public init(observer: Ref, label: String, health: Health, checks: [Check]) {
            self.observer = observer
            self.label = label
            self.health = health
            self.checks = checks
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            observer = (try? c.decodeIfPresent(Ref.self, forKey: .observer)) ?? Ref(id: "", name: "")
            label = c.text(.label) ?? observer.name
            health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
            checks = (try? c.decodeIfPresent([Check].self, forKey: .checks)) ?? []
        }
    }

    /// One check of the service, from one observer, with its own deadline.
    public struct Check: Sendable, Hashable, Decodable {
        public var id: String
        public var name: String
        public var kind: String
        public var endpoint: String
        public var health: Health
        public var freshness: String
        public var sampledAt: Date?
        public var validUntil: Date?
        /// The 24 h median and 95th percentile of the passing samples;
        /// `nil` when there are none, or past the check's deadline.
        public var latency: Latency?
        /// The share of the day it was up, 0 to 100; `nil` when unknown.
        public var up24h: Double?
        public var firstByte: String
        /// The colo the edge in front named in the newest response; `nil`
        /// when none, or past the check's deadline.
        public var colo: String?
        public var samples: Samples?

        enum CodingKeys: String, CodingKey {
            case id, name, kind, endpoint, health, freshness, sampledAt = "sampled_at", validUntil = "valid_until"
            case latency, up24h = "up_24h", firstByte = "first_byte", colo, samples
        }

        public init(id: String, name: String, kind: String = "", endpoint: String = "", health: Health,
                    freshness: String = "fresh", sampledAt: Date? = nil, validUntil: Date? = nil, latency: Latency? = nil,
                    up24h: Double? = nil, firstByte: String = "", colo: String? = nil, samples: Samples? = nil) {
            self.id = id
            self.name = name
            self.kind = kind
            self.endpoint = endpoint
            self.health = health
            self.freshness = freshness
            self.sampledAt = sampledAt
            self.validUntil = validUntil
            self.latency = latency
            self.up24h = up24h
            self.firstByte = firstByte
            self.colo = colo
            self.samples = samples
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id) ?? ""
            name = c.text(.name) ?? id
            kind = c.text(.kind) ?? ""
            endpoint = c.text(.endpoint) ?? ""
            health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
            freshness = c.text(.freshness) ?? ""
            sampledAt = c.timestamp(.sampledAt)
            validUntil = c.timestamp(.validUntil)
            latency = (try? c.decodeIfPresent(Latency.self, forKey: .latency)) ?? nil
            up24h = c.share(.up24h)
            firstByte = c.text(.firstByte) ?? ""
            colo = c.text(.colo).flatMap { $0.isEmpty ? nil : $0 }
            samples = (try? c.decodeIfPresent(Samples.self, forKey: .samples)) ?? nil
        }
    }

    public struct Latency: Sendable, Hashable, Decodable {
        public var p50: Double?
        public var p95: Double?

        enum CodingKeys: String, CodingKey { case p50 = "p50_ms", p95 = "p95_ms" }

        public init(p50: Double?, p95: Double?) {
            self.p50 = p50
            self.p95 = p95
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            p50 = c.duration(.p50)
            p95 = c.duration(.p95)
        }
    }

    /// A check's most recent samples, oldest first.
    public struct Samples: Sendable, Hashable, Decodable {
        public var interval: Double?
        /// `nil` when withheld: past the check's deadline nothing is drawn.
        public var slots: [Slot]?

        enum CodingKeys: String, CodingKey { case interval = "interval_seconds", slots }

        public init(interval: Double?, slots: [Slot]?) {
            self.interval = interval
            self.slots = slots
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            interval = c.duration(.interval)
            slots = (try? c.decodeIfPresent([Slot].self, forKey: .slots)) ?? nil
        }
    }

    /// One interval of a check's history, as `view.Strip` lays it out.
    public struct Slot: Sendable, Hashable, Decodable {
        public enum Outcome: String, Sendable, Hashable {
            case ok, fail, policy, error, unknown
            /// No sample was taken in that interval.
            case none
        }

        public var outcome: Outcome
        /// Only for `ok`: how long it took.
        public var elapsed: Double?

        enum CodingKeys: String, CodingKey { case outcome, elapsed = "elapsed_ms" }

        public init(_ outcome: Outcome, elapsed: Double? = nil) {
            self.outcome = outcome
            self.elapsed = outcome == .ok ? elapsed : nil
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            outcome = c.text(.outcome).flatMap(Outcome.init(rawValue:)) ?? .unknown
            elapsed = outcome == .ok ? c.duration(.elapsed) : nil
        }
    }

    /// How the service is reached.
    public struct Endpoint: Sendable, Hashable, Decodable {
        public var id: String
        public var network: String
        public var address: String
        /// `nil` where no check targets the address.
        public var health: Health?
        /// The edges and proxies in front, client side first.
        public var via: [Via]

        enum CodingKeys: String, CodingKey { case id, network, address, health, via }

        public init(id: String, network: String, address: String, health: Health?, via: [Via] = []) {
            self.id = id
            self.network = network
            self.address = address
            self.health = health
            self.via = via
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id) ?? ""
            network = c.text(.network) ?? ""
            address = c.text(.address) ?? ""
            health = c.text(.health).flatMap { $0.isEmpty ? nil : Health(rawValue: $0) ?? .unknown }
            via = (try? c.decodeIfPresent([Via].self, forKey: .via)) ?? []
        }
    }

    public struct Via: Sendable, Hashable, Decodable {
        public var id: String
        public var name: String
        public var kind: String
        public var provider: String

        enum CodingKeys: String, CodingKey { case id, name, kind, provider }

        public init(id: String, name: String, kind: String = "", provider: String = "") {
            self.id = id
            self.name = name
            self.kind = kind
            self.provider = provider
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id) ?? ""
            name = c.text(.name) ?? id
            kind = c.text(.kind) ?? ""
            provider = c.text(.provider) ?? ""
        }
    }

    /// Where the edge in front answered from over the day, and what its
    /// cache said, as shares `topo` worded: "SJC 50%".
    public struct AnsweredFrom: Sendable, Hashable, Decodable {
        public var pops: [String]
        public var cache: [String]

        enum CodingKeys: String, CodingKey { case pops, cache }

        public init(pops: [String], cache: [String] = []) {
            self.pops = pops
            self.cache = cache
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pops = (try? c.decodeIfPresent([String].self, forKey: .pops)) ?? []
            cache = (try? c.decodeIfPresent([String].self, forKey: .cache)) ?? []
        }
    }

    /// A service this one depends on, or one that depends on it.
    public struct Related: Sendable, Hashable, Decodable {
        public var id: String
        public var name: String
        public var health: Health
        public var affected: Bool?
        public var monitored: Bool?
        /// The name of the node it runs on.
        public var host: String

        enum CodingKeys: String, CodingKey { case id, name, health, affected, monitored, host }

        public init(id: String, name: String, health: Health, affected: Bool? = nil, monitored: Bool? = nil, host: String = "") {
            self.id = id
            self.name = name
            self.health = health
            self.affected = affected
            self.monitored = monitored
            self.host = host
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id) ?? ""
            name = c.text(.name) ?? id
            health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
            affected = try? c.decodeIfPresent(Bool.self, forKey: .affected)
            monitored = try? c.decodeIfPresent(Bool.self, forKey: .monitored)
            host = c.text(.host) ?? ""
        }
    }

    public var id: String
    public var name: String
    public var application: Ref?
    public var environment: String
    public var runtime: String
    public var health: Health
    /// `affected`, `cached` or empty.
    public var note: String
    public var evidence: String
    public var reason: String
    /// `false` when no check measures it; `nil` when not said.
    public var monitored: Bool?
    /// In a view scoped to one observer, whether another's checks measure
    /// it: then nothing seen here means not seen from here.
    public var elsewhere: Bool
    public var host: Host?
    public var seenFrom: [SeenFrom]
    public var endpoints: [Endpoint]
    public var answeredFrom: AnsweredFrom?
    public var dependsOn: [Related]
    public var usedBy: [Related]
    public var runbook: String
    public var memo: String

    enum CodingKeys: String, CodingKey {
        case id, name, application, environment, runtime, health, note, evidence, reason, monitored, elsewhere, host
        case seenFrom = "seen_from", endpoints, answeredFrom = "answered_from", dependsOn = "depends_on", usedBy = "used_by"
        case runbook, memo
    }

    public init(id: String, name: String, application: Ref? = nil, environment: String = "", runtime: String = "",
                health: Health, note: String = "", evidence: String = "", reason: String = "", monitored: Bool? = true,
                elsewhere: Bool = false, host: Host? = nil, seenFrom: [SeenFrom] = [], endpoints: [Endpoint] = [], answeredFrom: AnsweredFrom? = nil,
                dependsOn: [Related] = [], usedBy: [Related] = [], runbook: String = "", memo: String = "") {
        self.id = id
        self.name = name
        self.application = application
        self.environment = environment
        self.runtime = runtime
        self.health = health
        self.note = note
        self.evidence = evidence
        self.reason = reason
        self.monitored = monitored
        self.elsewhere = elsewhere
        self.host = host
        self.seenFrom = seenFrom
        self.endpoints = endpoints
        self.answeredFrom = answeredFrom
        self.dependsOn = dependsOn
        self.usedBy = usedBy
        self.runbook = runbook
        self.memo = memo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.text(.name) ?? id
        application = (try? c.decodeIfPresent(Ref.self, forKey: .application)) ?? nil
        environment = c.text(.environment) ?? ""
        runtime = c.text(.runtime) ?? ""
        health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        note = c.text(.note) ?? ""
        evidence = c.text(.evidence) ?? ""
        reason = c.text(.reason) ?? ""
        monitored = try? c.decodeIfPresent(Bool.self, forKey: .monitored)
        elsewhere = ((try? c.decodeIfPresent(Bool.self, forKey: .elsewhere)) ?? nil) ?? false
        host = (try? c.decodeIfPresent(Host.self, forKey: .host)) ?? nil
        seenFrom = try c.decodeIfPresent([SeenFrom].self, forKey: .seenFrom) ?? []
        endpoints = (try? c.decodeIfPresent([Endpoint].self, forKey: .endpoints)) ?? []
        answeredFrom = (try? c.decodeIfPresent(AnsweredFrom.self, forKey: .answeredFrom)) ?? nil
        dependsOn = (try? c.decodeIfPresent([Related].self, forKey: .dependsOn)) ?? []
        usedBy = (try? c.decodeIfPresent([Related].self, forKey: .usedBy)) ?? []
        runbook = c.text(.runbook) ?? ""
        memo = c.text(.memo) ?? ""
    }
}

extension ServiceCard {
    /// The card with each check's own deadline applied at `now` (PROTOCOL.md
    /// §3.3): past it, a check keeps its identity, `sampled_at` and
    /// deadline, its health turns unknown and its readings are withheld.
    /// One check's deadline never expires the card.
    public func applyingDeadlines(at now: Date, tolerance: TimeInterval) -> ServiceCard {
        var c = self
        let horizon = now.addingTimeInterval(tolerance)
        func lapsed(_ k: Check) -> Bool {
            (k.validUntil.map { now >= $0 || $0 > horizon } ?? false) || (k.sampledAt.map { $0 > horizon } ?? false)
        }
        c.seenFrom = seenFrom.map { o in
            var o = o
            o.checks = o.checks.map { k in
                guard lapsed(k) else { return k }
                var x = k
                x.health = .unknown
                x.freshness = "stale"
                x.latency = nil
                x.up24h = nil
                x.colo = nil
                x.samples = k.samples.map { Samples(interval: $0.interval, slots: nil) }
                return x
            }
            return o
        }
        return c
    }
}

/// A service with a card, for choosing services (`services.list`).
public struct ServiceListEntry: Sendable, Hashable, Decodable, Identifiable {
    public struct Host: Sendable, Hashable, Decodable {
        public var id: String
        public var name: String
        public var kind: String
        public var provider: String

        enum CodingKeys: String, CodingKey { case id, name, kind, provider }

        public init(id: String, name: String, kind: String = "", provider: String = "") {
            self.id = id
            self.name = name
            self.kind = kind
            self.provider = provider
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id) ?? ""
            name = c.text(.name) ?? id
            kind = c.text(.kind) ?? ""
            provider = c.text(.provider) ?? ""
        }
    }

    public var id: String
    public var name: String
    /// Its application's name; empty for none.
    public var application: String
    public var health: Health
    public var note: String
    public var monitored: Bool?
    public var host: Host?

    enum CodingKeys: String, CodingKey { case id, name, application, health, note, monitored, host }

    public init(id: String, name: String, application: String = "", health: Health = .unknown, note: String = "",
                monitored: Bool? = true, host: Host? = nil) {
        self.id = id
        self.name = name
        self.application = application
        self.health = health
        self.note = note
        self.monitored = monitored
        self.host = host
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.text(.name) ?? id
        application = c.text(.application) ?? ""
        health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        note = c.text(.note) ?? ""
        monitored = try? c.decodeIfPresent(Bool.self, forKey: .monitored)
        host = (try? c.decodeIfPresent(Host.self, forKey: .host)) ?? nil
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

    /// A duration or time in its unit: a number ≥ 0, or `nil` when absent,
    /// null or invalid.
    func duration(_ key: Key) -> Double? {
        guard let n = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil, n >= 0, n.isFinite else { return nil }
        return n
    }

    /// A percentage, 0 to 100, or `nil` when absent, null or invalid.
    func share(_ key: Key) -> Double? {
        guard let n = duration(key), n <= 100 else { return nil }
        return n
    }
}
