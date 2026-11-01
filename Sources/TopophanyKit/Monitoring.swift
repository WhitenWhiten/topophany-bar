import Foundation

/// Snapshot acquisition, independently of the health and age of its evidence.
public struct CollectorRead: Sendable, Hashable, Decodable {
    public var state: String
    public var attemptedAt: Date?
    public var completedAt: Date?
    public var lastSuccessAt: Date?
    public var durationMS: Int?
    public var consecutiveFailures: Int?
    public var stage: String
    public var code: String

    enum CodingKeys: String, CodingKey {
        case state, attemptedAt = "attempted_at", completedAt = "completed_at", lastSuccessAt = "last_success_at"
        case durationMS = "duration_ms", consecutiveFailures = "consecutive_failures", stage, code
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.text(.state) ?? "unknown"
        attemptedAt = c.timestamp(.attemptedAt); completedAt = c.timestamp(.completedAt); lastSuccessAt = c.timestamp(.lastSuccessAt)
        durationMS = c.count(.durationMS); consecutiveFailures = c.count(.consecutiveFailures)
        stage = c.text(.stage) ?? ""; code = c.text(.code) ?? ""
    }
}

public struct CheckDiagnostic: Sendable, Hashable, Decodable {
    public var outcome: String
    public var evidence: String
    public var pathEvidence: String
    public var stage: String
    public var code: String
    public var policyConfirmed: Bool
    public var facts: [String: String]
    public var expected: [String: String]
    enum CodingKeys: String, CodingKey {
        case outcome, evidence, pathEvidence = "path_evidence", stage, code, policyConfirmed = "policy_confirmed", facts, expected
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outcome = c.text(.outcome) ?? "unknown"; evidence = c.text(.evidence) ?? "unknown"
        pathEvidence = c.text(.pathEvidence) ?? ""; stage = c.text(.stage) ?? ""; code = c.text(.code) ?? ""
        policyConfirmed = (try? c.decodeIfPresent(Bool.self, forKey: .policyConfirmed)) ?? false
        facts = (try? c.decodeIfPresent([String: String].self, forKey: .facts)) ?? [:]
        expected = (try? c.decodeIfPresent([String: String].self, forKey: .expected)) ?? [:]
    }
}

public struct CheckCard: Sendable, Hashable, Decodable, Identifiable {
    public var check: ServiceCard.Check
    public var observer: ServiceCard.Ref
    public var service: String
    public var link: String
    public var path: String
    public var reason: String
    public var id: String { check.id }
    enum CodingKeys: String, CodingKey { case observer, service, link, path, reason }
    public init(from decoder: Decoder) throws {
        check = try ServiceCard.Check(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        observer = (try? c.decode(ServiceCard.Ref.self, forKey: .observer)) ?? .init(id: "", name: "")
        service = c.text(.service) ?? ""; link = c.text(.link) ?? ""; path = c.text(.path) ?? ""; reason = c.text(.reason) ?? ""
    }
}

public struct CheckListEntry: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var observer: String
    public var service: String?
    public var link: String?
    public var health: Health
    public var freshness: String
}

public struct LinkSummary: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var from: ServiceCard.Ref
    public var to: ServiceCard.Ref
    public var transport: String
    public var health: Health
    public var evidence: String
    public var reason: String
    public var affected: Bool
    public var sampledAt: Date?
    public var validUntil: Date?
    public var name: String { from.name + " → " + to.name }
    enum CodingKeys: String, CodingKey {
        case id, from, to, transport, health, evidence, reason, affected, sampledAt = "sampled_at", validUntil = "valid_until"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        from = try c.decode(ServiceCard.Ref.self, forKey: .from); to = try c.decode(ServiceCard.Ref.self, forKey: .to)
        transport = c.text(.transport) ?? ""; health = (try? c.decode(Health.self, forKey: .health)) ?? .unknown
        evidence = c.text(.evidence) ?? ""; reason = c.text(.reason) ?? ""
        affected = (try? c.decodeIfPresent(Bool.self, forKey: .affected)) ?? false
        sampledAt = c.timestamp(.sampledAt); validUntil = c.timestamp(.validUntil)
    }
}

public struct LinkCard: Sendable, Hashable, Decodable, Identifiable {
    public var summary: LinkSummary
    public var checks: [CheckCard]
    public var id: String { summary.id }
    enum CodingKeys: String, CodingKey { case checks }
    public init(from decoder: Decoder) throws {
        summary = try LinkSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checks = try c.decodeIfPresent([CheckCard].self, forKey: .checks) ?? []
    }
}

extension ServiceCard.Check {
    public func applyingDeadlines(at now: Date, tolerance: TimeInterval, required: Bool = false) -> Self {
        let horizon = now.addingTimeInterval(tolerance)
        let expired = validUntil.map { now >= $0 || $0 > horizon } ?? (required || diagnostic != nil)
        guard expired || (sampledAt.map { $0 > horizon } ?? false) else { return self }
        return withheld()
    }

    public func withheld() -> Self {
        var c = self
        c.health = .unknown; c.freshness = "stale"; c.latency = nil; c.up24h = nil; c.colo = nil; c.diagnostic = nil
        c.samples = samples.map { ServiceCard.Samples(interval: $0.interval, slots: nil) }
        return c
    }
}
