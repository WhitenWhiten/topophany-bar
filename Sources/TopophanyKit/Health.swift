import Foundation

/// A health as `topo` states it. The app never derives one: every value of
/// this type was decoded from a frame, or is `.unknown` because nothing
/// current was said.
public enum Health: String, Sendable, Hashable, Codable, CaseIterable {
    case up
    case degraded
    case down
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Health(rawValue: raw) ?? .unknown
    }

    /// The order `topo` lists entries in: down, degraded, unknown, up.
    public var severity: Int {
        switch self {
        case .down: 0
        case .degraded: 1
        case .unknown: 2
        case .up: 3
        }
    }
}

/// Counts of checks or services by health, exactly as `topo` sent them.
/// A count that wasn't sent is `nil`: unknown is never zero.
public struct HealthCounts: Sendable, Hashable, Codable {
    public var up: Int?
    public var warning: Int?
    public var down: Int?
    public var unknown: Int?

    public init(up: Int?, warning: Int?, down: Int?, unknown: Int?) {
        self.up = up
        self.warning = warning
        self.down = down
        self.unknown = unknown
    }

    /// All four counts, or `nil` when any of them is missing.
    public var complete: (up: Int, warning: Int, down: Int, unknown: Int)? {
        guard let up, let warning, let down, let unknown else { return nil }
        return (up, warning, down, unknown)
    }
}
