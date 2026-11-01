import Foundation
import Observation
import TopophanyKit

/// This Mac's own checks, read by a second `topo monitor stream` beside
/// whatever the panel reads: the collector, Beszel and Komari, or neither.
///
/// It runs only while a check is set up and the running `topo` reads them.
/// `stop()` ends its stream and a list in flight; a late reply from an
/// earlier `topo` or list can't replace a newer one.
@MainActor @Observable
public final class LocalReader {
    /// The checks `topo` has saved, in its order.
    public private(set) var checks: [LocalChecks.Entry] = []
    public private(set) var profileRevision = ""
    /// The last list or stream problem's code, until the next success.
    public private(set) var problem: String?
    /// The `topo` the checks are read with, once it reads them.
    public private(set) var path: String?
    public private(set) var engineStatus: EngineStatus = .stopped

    public typealias MakeEngine = @MainActor (_ path: String) -> any Engine
    public typealias MakeClient = @Sendable (_ path: String) -> LocalClient
    @ObservationIgnored private let makeEngine: MakeEngine
    @ObservationIgnored private let makeClient: MakeClient
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private var policy = ReaderPolicy()
    @ObservationIgnored private var engine: (any Engine)?
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var requestRevision = 0
    @ObservationIgnored private var requestID: String?
    /// Called after anything the panel shows changes.
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(clock: any WallClock = SystemClock(), makeClient: @escaping MakeClient = { LocalClient(path: $0) },
                makeEngine: @escaping MakeEngine = { ProcessEngine(configuration: .init(topoPath: $0)) }) {
        self.clock = clock; self.makeClient = makeClient; self.makeEngine = makeEngine
    }

    public var client: LocalClient? { path.map(makeClient) }

    /// Reads with the `topo` at `path`: lists its checks and streams them.
    /// The same `path` again only lists afresh.
    public func attach(path: String) {
        if self.path != path { stop(); self.path = path }
        reload()
    }

    /// Lists the checks again, as after a save, and follows them.
    public func reload() {
        guard let path else { return }
        generation += 1
        let g = generation, client = makeClient(path)
        listTask?.cancel()
        listTask = Task { [weak self] in
            do {
                let list = try await client.call(.list, as: LocalChecks.self)
                guard let self, self.generation == g, !Task.isCancelled else { return }
                self.checks = list.checks; self.profileRevision = list.profileRevision; self.problem = nil
                self.follow()
            } catch {
                guard let self, self.generation == g, !Task.isCancelled else { return }
                self.problem = (error as? SourceProblem)?.code ?? "command_cancelled"
                self.onChange?()
            }
        }
    }

    /// Ends the stream and any list in flight; what was read is forgotten.
    public func stop() {
        generation += 1
        listTask?.cancel(); listTask = nil
        endEngine()
        checks = []; profileRevision = ""; path = nil; problem = nil
        policy = ReaderPolicy()
        onChange?()
    }

    /// At quit: closes the stream's stdin at once, with no further updates.
    public func closeNow() {
        generation += 1
        onChange = nil
        listTask?.cancel(); listTask = nil
        endEngine()
    }

    /// The local reading as of `now`, or `nil` when nothing is set up.
    public func evaluate(at now: Date) -> Reading? {
        checks.isEmpty ? nil : policy.evaluate(at: now)
    }

    /// The pins of the cards it shows, in order.
    public var pins: [MonitorPin] { checks.map { MonitorPin(kind: .check, id: $0.check.id) } }

    private func follow() {
        requestRevision += 1
        guard let path, let request = TemplateCompiler().localRequest(checks.map(\.check), revision: requestRevision, profileRevision: profileRevision) else {
            endEngine(); policy = ReaderPolicy(); onChange?(); return
        }
        requestID = request.requestID
        if let engine {
            Task { try? await engine.update(request) }
        } else {
            let e = makeEngine(path)
            engine = e
            let stream = e.start(request)
            engineTask = Task { [weak self] in
                for await event in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(event)
                }
            }
        }
        onChange?()
    }

    private func endEngine() {
        engineTask?.cancel(); engineTask = nil
        if let old = engine {
            if let p = old as? ProcessEngine { p.closeInputNow() }
            Task { await old.stop() }
        }
        engine = nil; requestID = nil; engineStatus = .stopped
    }

    func handle(_ event: EngineEvent) {
        let now = clock.now()
        switch event {
        case .frame(let f, let line):
            guard f.requestID == requestID, f.source == "local" else { return }
            if f.lifecycle == .error {
                problem = f.error?.code ?? "configuration_failed"
                // Saved elsewhere since it was listed: list again.
                if problem == "profile_conflict" { reload() }
            } else if f.lifecycle == .running { problem = nil }
            policy.receive(f, line: line, at: now)
        case .status(let s):
            engineStatus = s
            switch s {
            case .running: policy.sourceStarted()
            case .restarting, .unavailable, .stopped: policy.sourceEnded(at: now)
            case .starting: break
            }
        case .sourceEnded: policy.sourceEnded(at: now)
        case .capabilities, .diagnostic, .diagnostics: return
        }
        onChange?()
    }
}
