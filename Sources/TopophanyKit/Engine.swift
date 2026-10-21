import Foundation
import Synchronization

/// Something that produces frames for a request: `topo monitor stream` as a
/// child process today, the same core linked as a library later. Nothing
/// above an engine knows which one it is.
public protocol Engine: AnyObject, Sendable {
    /// Starts the engine on a first request. Events arrive in order; the
    /// stream finishes after `stop()`.
    func start(_ request: Request) -> AsyncStream<EngineEvent>
    /// Replaces the running request atomically.
    func update(_ request: Request) async throws
    /// Ends the stream: stdin closes and `topo` exits.
    func stop() async
}

public enum EngineEvent: Sendable {
    case frame(Frame, line: Data)
    case status(EngineStatus)
    /// stdout ended; the process may still be exiting. Its evidence is
    /// unavailable immediately, independently of stderr and reaping.
    case sourceEnded
    /// The supervisor's successful probe, before the first request is sent.
    case capabilities(Capabilities)
    /// A line `topo` wrote to stderr, or a line that wasn't a frame. Shown,
    /// never parsed.
    case diagnostic(String)
    /// A bounded batch of diagnostics. Drain it when handling this event;
    /// frames and lifecycle events keep their own places in the stream.
    case diagnostics(EngineDiagnostics)
}

/// At most one pending notification and the latest 50 diagnostic lines,
/// even when the event consumer is busy. Diagnostics never displace frames.
public final class EngineDiagnostics: Sendable {
    private struct State: Sendable {
        var lines: [String] = []
        var notified = false
    }
    private let state = Mutex(State())

    public init() {}

    /// Returns true when the producer should enqueue a notification.
    public func append(_ line: String) -> Bool {
        state.withLock { s in
            s.lines.append(String(line.prefix(500)))
            if s.lines.count > 50 { s.lines.removeFirst(s.lines.count - 50) }
            guard !s.notified else { return false }
            s.notified = true
            return true
        }
    }

    public func drain() -> [String] {
        state.withLock { s in
            defer { s.lines.removeAll(keepingCapacity: true); s.notified = false }
            return s.lines
        }
    }
}

public enum EngineStatus: Sendable, Hashable {
    /// Looking for `topo` and checking what it supports.
    case starting
    case running(Running)
    /// The process ended; it starts again after `retryIn` seconds.
    case restarting(retryIn: TimeInterval, attempt: Int, reason: String)
    /// The engine can't run until something changes, such as the `topo`
    /// path setting.
    case unavailable(EngineProblem)
    case stopped

    public struct Running: Sendable, Hashable {
        public var pid: Int32
        public var path: String
        public var version: String
        public var startedAt: Date

        public init(pid: Int32, path: String, version: String, startedAt: Date) {
            self.pid = pid
            self.path = path
            self.version = version
            self.startedAt = startedAt
        }
    }

    /// Whether frames can be arriving.
    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

public enum EngineProblem: Error, Sendable, Hashable {
    /// No `topo` at the configured path or anywhere searched.
    case notFound(searched: [String])
    /// This `topo` has no `monitor stream`: it must be upgraded.
    case upgradeNeeded(path: String)
    /// `monitor stream` exists but lacks protocol 1 or a metric.
    case unsupported(path: String, version: String, missing: [String])
    case launchFailed(path: String, message: String)
}
