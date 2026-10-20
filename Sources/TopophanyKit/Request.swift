import Foundation

/// One request line on `topo monitor stream`'s stdin (PROTOCOL.md §2).
public struct Request: Sendable, Hashable, Codable {
    public var schema: Int = 1
    public var requestID: String
    /// `client` or `preview`.
    public var source: String
    public var credentials: String
    public var profile: String
    public var project: String
    public var observer: String
    /// `preview` only.
    public var scenario: Int?
    /// `preview` only: `en`, `ja` or `zh`.
    public var lang: String?
    public var interval: String
    public var template: Template

    enum CodingKeys: String, CodingKey {
        case schema, requestID = "request_id", source, credentials, profile, project, observer, scenario, lang, interval, template
    }

    public init(requestID: String, source: String = "client", credentials: String = "", profile: String = "",
                project: String = "", observer: String = "", scenario: Int? = nil, lang: String? = nil,
                interval: String = "5s", template: Template) {
        self.requestID = requestID
        self.source = source
        self.credentials = credentials
        self.profile = profile
        self.project = project
        self.observer = observer
        self.scenario = scenario
        self.lang = lang
        self.interval = interval
        self.template = template
    }

    /// The request as one NDJSON line, newline included.
    public func line() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var d = try e.encode(self)
        d.append(0x0A)
        return d
    }
}

/// `topo monitor`'s template schema 1, with the stream's additions.
public struct Template: Sendable, Hashable, Codable {
    public struct Bar: Sendable, Hashable, Codable {
        public var row: String
        public init(row: String) { self.row = row }
    }

    public var schema: Int = 1
    public var title: String
    public var bar: Bar
    public var rows: [TemplateRow]

    public init(title: String = "Topophany", bar: Bar = Bar(row: "status"), rows: [TemplateRow]) {
        self.title = title
        self.bar = bar
        self.rows = rows
    }
}

public struct TemplateRow: Sendable, Hashable, Codable {
    public struct Selector: Sendable, Hashable, Codable {
        public var check: String?
        public var collector: String?
        public var node: String?
        public var service: String?

        public init(check: String? = nil, collector: String? = nil, node: String? = nil, service: String? = nil) {
            self.check = check
            self.collector = collector
            self.node = node
            self.service = service
        }
    }

    public var id: String
    public var metric: String
    public var visual: String
    public var select: Selector?
    public var limit: Int?

    public init(id: String, metric: String, visual: String, select: Selector? = nil, limit: Int? = nil) {
        self.id = id
        self.metric = metric
        self.visual = visual
        self.select = select
        self.limit = limit
    }
}

/// What `topo monitor stream --capabilities` prints.
public struct Capabilities: Sendable, Hashable, Decodable {
    public struct Metric: Sendable, Hashable, Decodable {
        public var name: String
        public var visual: String?
        public var sources: [String]?
    }

    public var `protocol`: Int
    /// Every protocol served, when a later `topo` serves more than one.
    public var protocols: [Int]
    public var version: String
    public var sources: [String]
    public var visuals: [String]
    public var metrics: [Metric]
    /// Whether `--profiles` is served.
    public var profiles: Bool

    enum CodingKeys: String, CodingKey { case `protocol`, protocols, version, sources, visuals, metrics, profiles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        `protocol` = (try? c.decodeIfPresent(Int.self, forKey: .protocol)) ?? 0
        protocols = (try? c.decodeIfPresent([Int].self, forKey: .protocols)) ?? [`protocol`]
        version = c.text(.version) ?? ""
        sources = (try? c.decodeIfPresent([String].self, forKey: .sources)) ?? []
        visuals = (try? c.decodeIfPresent([String].self, forKey: .visuals)) ?? []
        metrics = (try? c.decodeIfPresent([Metric].self, forKey: .metrics)) ?? []
        profiles = (try? c.decodeIfPresent(Bool.self, forKey: .profiles)) ?? false
    }

    /// Whether `servers.list` is offered, for choosing nodes.
    public var listsServers: Bool { metrics.contains { $0.name == "servers.list" } }

    /// Whether `service.card` is offered, for pinned services and Service
    /// widgets. A `topo` without it draws everything else.
    public var cardsServices: Bool { metrics.contains { $0.name == "service.card" } }

    /// Whether `services.list` is offered, for choosing services.
    public var listsServices: Bool { metrics.contains { $0.name == "services.list" } }

    /// The metrics the panel draws.
    public static let required = ["summary.verdict", "observers.verdicts", "attention.list", "applications.list", "server.card"]

    /// Of `names`, those this `topo` doesn't offer.
    public func missing(_ names: [String] = Capabilities.required) -> [String] {
        let have = Set(metrics.map(\.name))
        return names.filter { !have.contains($0) }
    }

    /// Protocol 1 with every metric the panel draws.
    public var isUsable: Bool { (self.protocol == 1 || protocols.contains(1)) && missing().isEmpty }
}
