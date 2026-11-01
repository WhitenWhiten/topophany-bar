import Foundation

/// One of this Mac's own runtime checks that `topo` reads with no
/// collector: for now, the mihomo proxy engine's status API. Its secret
/// belongs only to a `topo local` command's stdin and `topo`'s own store.
public struct LocalCheck: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var adapter = "mihomo"
    /// The engine's status API on this Mac, as `http://127.0.0.1:9090`.
    public var url: String
    public var intervalSeconds = 30
    public var timeoutSeconds = 5
    public var staleSeconds = 90
    /// The proxy group whose choice is followed; empty for none.
    public var rootProxy = ""
    /// `rule`, `global`, `direct`, or empty for no expectation.
    public var expectedMode = ""
    public var expectedTUN: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, adapter, url, intervalSeconds = "interval_seconds", timeoutSeconds = "timeout_seconds", staleSeconds = "stale_seconds"
        case rootProxy = "root_proxy", expectedMode = "expected_mode", expectedTUN = "expected_tun"
    }

    /// mihomo's own default; proxy apps often choose another port.
    public static let defaultURL = "http://127.0.0.1:9090"

    public init(id: String = "lc-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16),
                name: String = "", url: String = LocalCheck.defaultURL) {
        self.id = id; self.name = name; self.url = url
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.text(.name) ?? id
        adapter = c.text(.adapter) ?? "mihomo"
        url = c.text(.url) ?? ""
        intervalSeconds = c.count(.intervalSeconds) ?? 30
        timeoutSeconds = c.count(.timeoutSeconds) ?? 5
        staleSeconds = c.count(.staleSeconds) ?? 90
        rootProxy = c.text(.rootProxy) ?? ""
        expectedMode = c.text(.expectedMode) ?? ""
        expectedTUN = try? c.decodeIfPresent(Bool.self, forKey: .expectedTUN)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(adapter, forKey: .adapter); try c.encode(url, forKey: .url)
        try c.encode(intervalSeconds, forKey: .intervalSeconds); try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try c.encode(staleSeconds, forKey: .staleSeconds); try c.encode(rootProxy, forKey: .rootProxy)
        try c.encode(expectedMode, forKey: .expectedMode)
        // An explicit null: no expectation, rather than an omitted field.
        try c.encode(expectedTUN, forKey: .expectedTUN)
    }

    /// Whether `url` names this Mac: a loopback address or `localhost`,
    /// with nothing after the port. `topo` checks the same and decides.
    public static func isLocal(_ url: String) -> Bool {
        guard let u = URLComponents(string: url), ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
              let host = u.host?.lowercased(), u.user == nil, u.password == nil, u.query == nil, u.fragment == nil,
              u.path.isEmpty || u.path == "/" else { return false }
        if host == "localhost" || host == "::1" || host == "[::1]" { return true }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy { UInt8($0) != nil }
    }
}

/// `topo local list --json`.
public struct LocalChecks: Sendable, Decodable {
    public struct Entry: Sendable, Decodable, Identifiable {
        public var check: LocalCheck
        /// `token` when a secret is saved, `none` otherwise.
        public var authMode: String
        public var id: String { check.id }
        enum CodingKeys: String, CodingKey { case check, authMode = "auth_mode" }
    }
    public var profileRevision: String
    public var checks: [Entry]
    public init(profileRevision: String = "", checks: [Entry] = []) { self.profileRevision = profileRevision; self.checks = checks }
    enum CodingKeys: String, CodingKey { case profileRevision = "profile_revision", checks }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profileRevision = c.text(.profileRevision) ?? ""
        checks = try c.decodeIfPresent([Entry].self, forKey: .checks) ?? []
    }
}

/// `topo local inspect`: what the engine said, read once.
public struct LocalInspection: Sendable, Decodable {
    public struct Engine: Sendable, Decodable, Hashable {
        public var version: String
        public var mode: String
        public var tun: Bool?
        enum CodingKeys: String, CodingKey { case version, mode, tun }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = c.text(.version) ?? ""; mode = c.text(.mode) ?? ""
            tun = try? c.decodeIfPresent(Bool.self, forKey: .tun)
        }
    }
    public struct Group: Sendable, Decodable, Hashable, Identifiable {
        public var name: String
        public var type: String
        public var id: String { name }
    }
    public var check: LocalCheck
    public var engine: Engine
    public var groups: [Group]
    public var truncated: Bool
    public var warnings: [String]
    enum CodingKeys: String, CodingKey { case check, engine, groups, truncated, warnings }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        check = try c.decode(LocalCheck.self, forKey: .check)
        engine = try c.decode(Engine.self, forKey: .engine)
        groups = try c.decodeIfPresent([Group].self, forKey: .groups) ?? []
        truncated = (try? c.decodeIfPresent(Bool.self, forKey: .truncated)) ?? false
        warnings = (try? c.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }
}

/// `topo local save` and `remove`.
public struct LocalChanged: Sendable, Decodable {
    public var profileRevision: String
    public var checkID: String
    enum CodingKeys: String, CodingKey { case profileRevision = "profile_revision", checkID = "check_id" }
}

extension TemplateCompiler {
    /// Row IDs of the local stream, by position.
    public static func localRow(_ index: Int) -> String { "local-\(index + 1)" }

    /// The local stream's request: each of this Mac's checks with its
    /// history. There are at most a handful, read by `topo` on this Mac.
    public func localRequest(_ checks: [LocalCheck], revision: Int, profileRevision: String) -> Request? {
        guard !checks.isEmpty else { return nil }
        let rows = checks.enumerated().map { i, c in
            TemplateRow(id: Self.localRow(i), metric: "check.card", visual: "card", select: .init(check: c.id), history: true)
        }
        var r = Request(requestID: "local-\(revision)", source: "local", template: Template(bar: .init(row: rows[0].id), rows: rows))
        if !profileRevision.isEmpty { r.profileRevision = profileRevision }
        return r
    }
}
