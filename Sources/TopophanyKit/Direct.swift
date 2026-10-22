import Foundation

/// D1 public configuration. Authentication material belongs only to a command's stdin.
public struct DirectSource: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var adapter = "beszel"
    public var url: String
    public var caFile = ""
    public var intervalSeconds = 60
    public var timeoutSeconds = 8
    public var staleSeconds = 180
    public var maxAgeSeconds = 180
    enum CodingKeys: String, CodingKey {
        case id, name, adapter, url, caFile = "ca_file", intervalSeconds = "interval_seconds"
        case timeoutSeconds = "timeout_seconds", staleSeconds = "stale_seconds", maxAgeSeconds = "max_age_seconds"
    }
    public init(id: String = "bs-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), name: String = "", url: String = "") {
        self.id = id; self.name = name; self.url = url
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        adapter = try c.decode(String.self, forKey: .adapter)
        url = try c.decode(String.self, forKey: .url)
        caFile = try c.decodeIfPresent(String.self, forKey: .caFile) ?? ""
        intervalSeconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 60
        timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 8
        staleSeconds = try c.decodeIfPresent(Int.self, forKey: .staleSeconds) ?? 180
        maxAgeSeconds = try c.decodeIfPresent(Int.self, forKey: .maxAgeSeconds) ?? 180
    }
}

public struct DirectNode: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var objectID: String
    public var name: String
    enum CodingKeys: String, CodingKey { case id, objectID = "object_id", name }
}
public struct DirectProfiles: Sendable, Decodable {
    public var profiles: [DirectProfile]
}
public struct DirectProfile: Sendable, Decodable, Identifiable {
    public var profile: String
    public var project: String
    public var profileRevision: String
    public var datasetID: String
    public var sources: [Entry]
    public var id: String { profile }
    public struct Entry: Sendable, Decodable, Identifiable {
        public var source: DirectSource
        public var authMode: String
        public var selectedObjects: [String]
        public var nodes: [DirectNode]
        public var id: String { source.id }
        enum CodingKeys: String, CodingKey { case source, authMode = "auth_mode", selectedObjects = "selected_objects", nodes }
    }
    enum CodingKeys: String, CodingKey {
        case profile, project, profileRevision = "profile_revision", datasetID = "dataset_id", sources
    }
}
public struct DirectInspection: Sendable, Decodable {
    public struct System: Sendable, Decodable, Hashable, Identifiable { public var id: String; public var name: String }
    public struct Limits: Sendable, Decodable {
        public var maxSelected: Int
        enum CodingKeys: String, CodingKey { case maxSelected = "max_selected" }
    }
    public var source: DirectSource
    public var systems: [System]
    public var truncated: Bool
    public var limits: Limits
    public var warnings: [String]
}
public struct DirectSaved: Sendable, Decodable {
    public var profile: String
    public var profileRevision: String
    public var datasetID: String
    public var sourceID: String
    public var nodes: [DirectNode]
    enum CodingKeys: String, CodingKey { case profile, profileRevision = "profile_revision", datasetID = "dataset_id", sourceID = "source_id", nodes }
}
public struct DirectRemoved: Sendable, Decodable {
    public var profile: String
    public var profileRevision: String
    public var datasetID: String
    public var sourceID: String
    enum CodingKeys: String, CodingKey { case profile, profileRevision = "profile_revision", datasetID = "dataset_id", sourceID = "source_id" }
}
public struct SourceEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    public var schema: Int
    public var requestID: String
    public var ok: Bool
    public var data: Value?
    public var error: SourceProblem?
    enum CodingKeys: String, CodingKey { case schema, requestID = "request_id", ok, data, error }
}
/// Do not surface upstream message text: even malformed peers must not expose a secret.
public struct SourceProblem: Error, Sendable, Decodable, Equatable {
    public var code: String
    public var retryable: Bool
    public init(code: String, retryable: Bool = false) { self.code = code; self.retryable = retryable }
}

public struct Origin: Sendable, Hashable, Decodable {
    public var adapter: String
    public var sourceID: String
    public var name: String
    public var objectID: String
    enum CodingKeys: String, CodingKey { case adapter, sourceID = "source_id", name, objectID = "object_id" }
}

public struct SourcesStatus: Sendable, Hashable, Decodable {
    public struct Counts: Sendable, Hashable, Decodable {
        public var sources: Int?
        public var selected: Int?
        public var current: Int?
        public var stale: Int?
        public var missing: Int?
        public var attention: Int?
    }
    public struct Source: Sendable, Hashable, Decodable, Identifiable {
        public var id: String
        public var name: String
        public var adapter: String
        public var state: String
        public var code: String?
        public var lastAttemptAt: Date?
        public var lastContactAt: Date?
        public var contactValidUntil: Date?
        public var nextRetryAt: Date?
        public var counts: Counts?
        enum CodingKeys: String, CodingKey {
            case id, name, adapter, state, code, counts, lastAttemptAt = "last_attempt_at", lastContactAt = "last_contact_at"
            case contactValidUntil = "contact_valid_until", nextRetryAt = "next_retry_at"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = c.text(.name) ?? id
            adapter = c.text(.adapter) ?? ""
            state = c.text(.state) ?? ""
            code = c.text(.code)
            counts = try? c.decodeIfPresent(Counts.self, forKey: .counts)
            lastAttemptAt = c.timestamp(.lastAttemptAt); lastContactAt = c.timestamp(.lastContactAt)
            contactValidUntil = c.timestamp(.contactValidUntil); nextRetryAt = c.timestamp(.nextRetryAt)
        }
    }
    public var state: String
    public var counts: Counts?
    public var sources: [Source]
}
