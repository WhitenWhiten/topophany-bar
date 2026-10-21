import Foundation
import Synchronization
import TopophanyKit

/// Runs `topo monitor stream` as a child process: requests on its stdin,
/// frames from its stdout (PROTOCOL.md §1).
///
/// 1. Finds `topo` (`TopoLocator`).
/// 2. Checks `--capabilities` for protocol 1 and the metrics the panel draws.
/// 3. Starts the stream and writes the current request.
/// 4. When the process ends, restarts it after 1, 2, 4 … up to 30 s.
/// 5. `stop()` closes stdin; `topo` writes its final frame and exits.
public final class ProcessEngine: Engine {
    public struct Configuration: Sendable {
        /// The `topo` path setting; empty to search.
        public var topoPath: String
        public var minimumBackoff: TimeInterval = 1
        public var maximumBackoff: TimeInterval = 30
        /// How long a process must run before the backoff starts over.
        public var healthyAfter: TimeInterval = 60
        /// How long to wait before looking for `topo` again when it can't run.
        public var unavailableRetry: TimeInterval = 30
        /// `PATH` from the login shell; replaced in tests.
        public var shellPath: @Sendable () -> String?
        /// The copies the app downloaded, searched last.
        public var downloads: TopoDownloads?

        public init(topoPath: String, shellPath: @escaping @Sendable () -> String? = { TopoLocator.loginShellPATH() },
                    downloads: TopoDownloads? = nil) {
            self.topoPath = topoPath
            self.shellPath = shellPath
            self.downloads = downloads
        }
    }

    private struct State: Sendable {
        var request: Request?
        var continuation: AsyncStream<EngineEvent>.Continuation?
        var stdin: FileHandle?
        var process: Process?
        var stopping = false
        var started = false
    }

    public let configuration: Configuration
    private let clock: any WallClock
    private let state = Mutex(State())
    private let diagnostics = EngineDiagnostics()
    private let shellPath: @Sendable () -> String?

    public init(configuration: Configuration, clock: any WallClock = SystemClock()) {
        self.configuration = configuration
        self.clock = clock
        let resolve = configuration.shellPath
        let cache = Mutex<String??>(nil)
        shellPath = {
            if let cached = cache.withLock({ $0 }) { return cached }
            let p = resolve()
            cache.withLock { $0 = .some(p) }
            return p
        }
    }

    public func start(_ request: Request) -> AsyncStream<EngineEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        let first = state.withLock { s -> Bool in
            guard !s.started else { return false }
            s.started = true
            s.request = request
            s.continuation = continuation
            return true
        }
        guard first else {
            continuation.finish()
            return stream
        }
        Thread.detachNewThread { [self] in supervise() }
        return stream
    }

    /// Writes the request to the running process. A process that has just
    /// ended gets it when it is restarted.
    public func update(_ request: Request) async throws {
        let line = try request.line()
        let stdin = state.withLock { s -> FileHandle? in
            s.request = request
            return s.stdin
        }
        try? stdin?.write(contentsOf: line)
    }

    public func stop() async {
        closeInputNow()
        // Wait for topo's final frame and exit; the supervisor finishes the
        // stream.
        for _ in 0..<40 {
            if state.withLock({ $0.continuation == nil }) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let p = state.withLock { $0.process }
        if let p, p.isRunning {
            p.terminate()
            for _ in 0..<20 {
                if !p.isRunning { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }

    /// Closes `topo`'s stdin at once, as the app quits. `topo` writes its
    /// final frame and exits; nothing is restarted.
    public func closeInputNow() {
        let stdin = state.withLock { s -> FileHandle? in
            s.stopping = true
            defer { s.stdin = nil }
            return s.stdin
        }
        try? stdin?.close()
    }

    private var stopping: Bool { state.withLock { $0.stopping } }

    private func yield(_ e: EngineEvent) {
        _ = state.withLock { $0.continuation }?.yield(e)
    }

    private func diagnose(_ line: String) {
        if diagnostics.append(line) { yield(.diagnostics(diagnostics)) }
    }

    // MARK: supervision

    private func supervise() {
        var attempt = 0
        let locator = TopoLocator(setting: configuration.topoPath, shellPath: shellPath, downloads: configuration.downloads)
        while !stopping {
            yield(.status(.starting))
            let found: TopoLocator.Found
            switch locator.locate() {
            case .failure(let problem):
                yield(.status(.unavailable(problem)))
                pause(configuration.unavailableRetry)
                continue
            case .success(let f):
                found = f
            }
            let version: String
            switch Self.check(found.path) {
            case .failure(let problem):
                yield(.status(.unavailable(problem)))
                pause(configuration.unavailableRetry)
                continue
            case .success(let caps):
                version = caps.version
            }
            if stopping { break }
            let began = clock.now()
            let reason = runOnce(path: found.path, version: version)
            if stopping { break }
            if clock.now().timeIntervalSince(began) >= configuration.healthyAfter { attempt = 0 }
            let delay = min(configuration.maximumBackoff, configuration.minimumBackoff * pow(2, Double(attempt)))
            attempt += 1
            yield(.status(.restarting(retryIn: delay, attempt: attempt, reason: reason)))
            pause(delay)
        }
        let c = state.withLock { s -> AsyncStream<EngineEvent>.Continuation? in
            defer { s.continuation = nil }
            return s.continuation
        }
        c?.yield(.status(.stopped))
        c?.finish()
    }

    /// Sleeps, waking early when stopped.
    private func pause(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while !stopping, Date() < end {
            Thread.sleep(forTimeInterval: min(0.1, max(0, end.timeIntervalSinceNow)))
        }
    }

    /// `topo monitor stream --capabilities`: protocol 1 and every metric the
    /// panel draws.
    public static func check(_ path: String, timeout: TimeInterval = 10) -> Result<Capabilities, EngineProblem> {
        guard let out = Subprocess.run(path, ["monitor", "stream", "--capabilities"], timeout: timeout) else {
            return .failure(.launchFailed(path: path, message: "topo didn't answer --capabilities"))
        }
        guard out.status == 0 else { return .failure(.upgradeNeeded(path: path)) }
        let line = out.stdout.split(separator: 0x0A).first.map { Data($0) } ?? Data()
        guard let caps = try? JSONDecoder().decode(Capabilities.self, from: line) else {
            return .failure(.upgradeNeeded(path: path))
        }
        guard caps.isUsable else {
            return .failure(.unsupported(path: path, version: caps.version, missing: caps.missing()))
        }
        return .success(caps)
    }

    /// `topo monitor stream --profiles`: the saved profiles, by name and
    /// project. Only for a `topo` whose capabilities say it's served.
    public static func profiles(_ path: String, timeout: TimeInterval = 5) -> ProfileList? {
        guard let out = Subprocess.run(path, ["monitor", "stream", "--profiles"], timeout: timeout), out.status == 0 else {
            return nil
        }
        let line = out.stdout.split(separator: 0x0A).first.map { Data($0) } ?? Data()
        return try? JSONDecoder().decode(ProfileList.self, from: line)
    }

    /// Runs one process to its end. Returns why it ended.
    private func runOnce(path: String, version: String) -> String {
        let p = Process()
        p.executableURL = URL(filePath: path)
        p.arguments = ["monitor", "stream"]
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        p.environment = env
        p.qualityOfService = .utility
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        // A write to a process that has gone fails instead of raising SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let exited = DispatchSemaphore(value: 0)
        let outputOrExit = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal(); outputOrExit.signal() }
        do {
            try p.run()
        } catch {
            return "couldn't start \(path): \(error.localizedDescription)"
        }
        let request = state.withLock { s -> Request? in
            s.process = p
            s.stdin = s.stopping ? nil : input.fileHandleForWriting
            return s.request
        }
        if stopping { try? input.fileHandleForWriting.close() }
        if let request, let line = try? request.line(), !stopping {
            try? input.fileHandleForWriting.write(contentsOf: line)
        }
        yield(.status(.running(.init(pid: p.processIdentifier, path: path, version: version, startedAt: clock.now()))))

        let stdoutFinished = DispatchSemaphore(value: 0)
        let stderrFinished = DispatchSemaphore(value: 0)
        let stdoutControl = ReadControl()
        let stderrControl = ReadControl()
        Thread.detachNewThread { [self] in
            readFrames(output.fileHandleForReading, control: stdoutControl)
            yield(.sourceEnded)
            stdoutFinished.signal()
            outputOrExit.signal()
        }
        Thread.detachNewThread { [self] in
            readDiagnostics(errors.fileHandleForReading, control: stderrControl)
            stderrFinished.signal()
        }
        // stdout alone ends the source. A descendant may inherit either
        // pipe, so neither reader may wait forever after topo exits.
        outputOrExit.wait()
        if stdoutFinished.wait(timeout: .now() + 0.25) == .timedOut {
            stdoutControl.stop()
            _ = stdoutFinished.wait(timeout: .now() + 1)
        }
        var reaped = exited.wait(timeout: .now() + 2) == .success
        if !reaped, p.isRunning {
            p.terminate()
            reaped = exited.wait(timeout: .now() + 1) == .success
        }
        if !reaped, p.isRunning {
            kill(p.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 1)
        }
        if stderrFinished.wait(timeout: .now() + 0.25) == .timedOut {
            stderrControl.stop()
            _ = stderrFinished.wait(timeout: .now() + 1)
        }
        state.withLock { s in
            s.process = nil
            s.stdin = nil
        }
        try? input.fileHandleForWriting.close()
        guard !p.isRunning else { return "topo did not exit after stdout closed" }
        switch p.terminationReason {
        case .uncaughtSignal: return "topo ended by signal \(p.terminationStatus)"
        default: return p.terminationStatus == 0 ? "topo exited" : "topo exited with status \(p.terminationStatus)"
        }
    }

    private final class ReadControl: Sendable {
        private let stopped = Mutex(false)
        let wake = Pipe()
        var isStopped: Bool { stopped.withLock { $0 } }
        func stop() {
            let first = stopped.withLock { s in
                guard !s else { return false }
                s = true
                return true
            }
            if first { try? wake.fileHandleForWriting.write(contentsOf: Data([1])) }
        }
    }

    /// A cancellation pipe wakes a blocked reader without periodic polling,
    /// even if a descendant retains stdout or stderr.
    private func readChunks(_ handle: FileHandle, control: ReadControl, consume: (Data) -> Void) {
        let fd = handle.fileDescriptor
        var descriptors = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
                           pollfd(fd: control.wake.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)]
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while !control.isStopped {
            let ready = poll(&descriptors, 2, -1)
            if ready < 0, errno == EINTR { continue }
            guard ready > 0, !control.isStopped, descriptors[0].revents & Int16(POLLNVAL) == 0 else { break }
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            consume(Data(buffer[0..<n]))
        }
    }

    private func readFrames(_ handle: FileHandle, control: ReadControl) {
        var decoder = FrameDecoder()
        readChunks(handle, control: control) { chunk in
            emit(decoder.feed(chunk))
        }
        emit(decoder.finish())
    }

    private func emit(_ outputs: [FrameDecoder.Output]) {
        for o in outputs {
            switch o {
            case .frame(let f, let line): yield(.frame(f, line: line))
            case .problem(.oversized(let bytes)): diagnose("dropped a frame of \(bytes) bytes, over the 1 MiB limit")
            case .problem(.malformed(let why)): diagnose("a line on stdout wasn't a frame: \(why)")
            }
        }
    }

    private func readDiagnostics(_ handle: FileHandle, control: ReadControl) {
        var pending = Data()
        readChunks(handle, control: control) { d in
            pending.append(d)
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...nl)
                if !line.isEmpty { diagnose(line) }
            }
            if pending.count > 4096 { pending.removeAll() }
        }
    }
}
