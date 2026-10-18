import Foundation

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
    /// A line `topo` wrote to stderr, or a line that wasn't a frame. Shown,
    /// never parsed.
    case diagnostic(String)
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
