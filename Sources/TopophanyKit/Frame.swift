import Foundation

/// One frame of `topo monitor stream`: the panel output schema 1
/// (PROTOCOL.md §3). Unknown fields are ignored.
public struct Frame: Sendable, Hashable, Decodable {
    public enum Lifecycle: Sendable, Hashable {
        case running, error, stopped
        case other(String)

        init(_ raw: String) {
            switch raw {
            case "running": self = .running
            case "error": self = .error
            case "stopped": self = .stopped
            default: self = .other(raw)
            }
        }
    }

    public struct Problem: Sendable, Hashable, Decodable {
        public var code: String
        public var message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public var schema: Int
    public var name: String
    public var requestID: String
    public var configRevision: String
    public var instance: String
    public var sequence: UInt64?
    public var source: String
    public var project: String
    public var observer: String
    public var lifecycle: Lifecycle
    public var generatedAt: Date?
    public var publisherExpiresAt: Date?
    public var title: String
    public var barRow: String
    public var rows: [Row]
    public var error: Problem?

    enum CodingKeys: String, CodingKey {
        case schema, name, requestID = "request_id", configRevision = "config_revision", instance, sequence, source
        case project, observer, lifecycle, generatedAt = "generated_at", publisherExpiresAt = "publisher_expires_at"
        case title, barRow = "bar_row", rows, error
    }

    public init(schema: Int = 1, name: String = "stream", requestID: String = "", configRevision: String = "",
                instance: String = "", sequence: UInt64? = nil, source: String = "client", project: String = "",
                observer: String = "", lifecycle: Lifecycle = .running, generatedAt: Date?, publisherExpiresAt: Date?,
                title: String = "Topophany", barRow: String = "status", rows: [Row], error: Problem? = nil) {
        self.schema = schema
        self.name = name
        self.requestID = requestID
        self.configRevision = configRevision
        self.instance = instance
        self.sequence = sequence
        self.source = source
        self.project = project
        self.observer = observer
        self.lifecycle = lifecycle
        self.generatedAt = generatedAt
        self.publisherExpiresAt = publisherExpiresAt
        self.title = title
        self.barRow = barRow
        self.rows = rows
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        name = c.text(.name) ?? ""
        requestID = c.text(.requestID) ?? ""
        configRevision = c.text(.configRevision) ?? ""
        instance = c.text(.instance) ?? ""
        sequence = (try? c.decodeIfPresent(UInt64.self, forKey: .sequence)) ?? nil
        source = c.text(.source) ?? ""
        project = c.text(.project) ?? ""
        observer = c.text(.observer) ?? ""
        lifecycle = Lifecycle(c.text(.lifecycle) ?? "")
        generatedAt = c.timestamp(.generatedAt)
        publisherExpiresAt = c.timestamp(.publisherExpiresAt)
        title = c.text(.title) ?? ""
        barRow = c.text(.barRow) ?? ""
        rows = try c.decodeIfPresent([Row].self, forKey: .rows) ?? []
        error = try? c.decodeIfPresent(Problem.self, forKey: .error)
    }

    public func row(_ id: String) -> Row? { rows.first { $0.id == id } }
}

/// A row: its template fields, echoed, and the value `topo` resolved for it.
public struct Row: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var label: String
    public var metric: String
    public var visual: String
    public var select: TemplateRow.Selector?
    public var limit: Int?

    public var value: RowValue
    public var unit: String
    public var text: String
    public var health: Health
    public var freshness: String
    public var reason: String
    public var sampledAt: Date?
    public var validUntil: Date?

    enum CodingKeys: String, CodingKey {
        case id, label, metric, visual, select, limit
        case value, unit, text, health, freshness, reason, sampledAt = "sampled_at", validUntil = "valid_until"
    }

    public init(id: String, label: String = "", metric: String, visual: String = "", select: TemplateRow.Selector? = nil,
                limit: Int? = nil, value: RowValue, unit: String = "", text: String = "", health: Health,
                freshness: String = "fresh", reason: String = "", sampledAt: Date? = nil, validUntil: Date?) {
        self.id = id
        self.label = label
        self.metric = metric
        self.visual = visual
        self.select = select
        self.limit = limit
        self.value = value
        self.unit = unit
        self.text = text
        self.health = health
        self.freshness = freshness
        self.reason = reason
        self.sampledAt = sampledAt
        self.validUntil = validUntil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = c.text(.label) ?? ""
        metric = c.text(.metric) ?? ""
        visual = c.text(.visual) ?? ""
        select = try? c.decodeIfPresent(TemplateRow.Selector.self, forKey: .select)
        limit = (try? c.decodeIfPresent(Int.self, forKey: .limit)) ?? nil
        value = RowValue(metric: metric, container: c, key: .value)
        unit = c.text(.unit) ?? ""
        text = c.text(.text) ?? ""
        health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        freshness = c.text(.freshness) ?? ""
        reason = c.text(.reason) ?? ""
        sampledAt = c.timestamp(.sampledAt)
        validUntil = c.timestamp(.validUntil)
    }
}

/// A row's value, typed by its metric.
public enum RowValue: Sendable, Hashable {
    /// `null`, or absent: nothing current is known.
    case none
    case verdict(Verdict)
    case observers([ObserverVerdict])
    case attention(AttentionList)
    case applications([Application])
    case serverCard(ServerCard)
    case servers([ServerListEntry])
    case serviceCard(ServiceCard)
    case services([ServiceListEntry])
    case map(MapGraph)
    /// A metric the panel doesn't draw.
    case other(JSONValue)
    /// The value didn't have its metric's shape; drawn as unknown.
    case malformed

    init(metric: String, container c: KeyedDecodingContainer<Row.CodingKeys>, key: Row.CodingKeys) {
        guard c.contains(key), (try? c.decodeNil(forKey: key)) == false else {
            self = .none
            return
        }
        do {
            switch metric {
            case "summary.verdict": self = .verdict(try c.decode(Verdict.self, forKey: key))
            case "observers.verdicts": self = .observers(try c.decode([ObserverVerdict].self, forKey: key))
            case "attention.list": self = .attention(try c.decode(AttentionList.self, forKey: key))
            case "applications.list": self = .applications(try c.decode([Application].self, forKey: key))
            case "server.card": self = .serverCard(try c.decode(ServerCard.self, forKey: key))
            case "servers.list": self = .servers(try c.decode([ServerListEntry].self, forKey: key))
            case "service.card": self = .serviceCard(try c.decode(ServiceCard.self, forKey: key))
            case "services.list": self = .services(try c.decode([ServiceListEntry].self, forKey: key))
            case "map.graph": self = .map(try c.decode(MapGraph.self, forKey: key))
            default: self = .other(try c.decode(JSONValue.self, forKey: key))
            }
        } catch {
            self = .malformed
        }
    }

    public var isKnown: Bool {
        switch self {
        case .none, .malformed: false
        default: true
        }
    }
}
