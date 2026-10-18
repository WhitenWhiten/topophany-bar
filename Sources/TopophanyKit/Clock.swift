import Foundation
import Synchronization

/// The consumer's clock. Deadlines are always checked against it, never
/// against a time `topo` sent.
public protocol WallClock: Sendable {
    func now() -> Date
}

public struct SystemClock: WallClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// A clock that moves only when told to: for tests and fixture replay.
public final class ManualClock: WallClock {
    private let current: Mutex<Date>

    public init(_ start: Date) { current = Mutex(start) }

    public func now() -> Date { current.withLock { $0 } }

    public func set(_ date: Date) { current.withLock { $0 = date } }

    public func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}
