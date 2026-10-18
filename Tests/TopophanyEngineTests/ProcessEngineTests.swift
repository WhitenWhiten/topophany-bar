import Foundation
import Synchronization
import Testing
@testable import TopophanyEngine
@testable import TopophanyKit

/// Records a stream's events as they arrive.
final class Recorder: Sendable {
    private final class Box: Sendable {
        let events = Mutex<[EngineEvent]>([])
    }

    private let box = Box()
    private let task: Task<Void, Never>

    init(_ stream: AsyncStream<EngineEvent>) {
        let box = self.box
        task = Task {
            for await e in stream { box.events.withLock { $0.append(e) } }
        }
    }

    var all: [EngineEvent] { box.events.withLock { $0 } }

    var frames: [Frame] { TopophanyEngineTests.frames(all) }

    var statuses: [EngineStatus] { all.compactMap { if case .status(let s) = $0 { s } else { nil } } }

    @discardableResult
    func wait(timeout: TimeInterval = 10, until done: @Sendable ([EngineEvent]) -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if done(all) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return done(all)
    }

    func finished() async { await task.value }
}

/// A stand-in for `topo` that speaks just enough of PROTOCOL.md: one frame
/// per request line, echoing its ID; a request ID containing "crash" makes
/// it exit 3; EOF on stdin ends it with a stopped frame.
enum FakeTopo {
    static let script = #"""
    #!/bin/sh
    if [ "$1 $2 $3" = "monitor stream --capabilities" ]; then
      echo '{"protocol":1,"version":"9.9.9-fake","sources":["client","preview"],"visuals":["status","list","card"],"metrics":[{"name":"summary.verdict"},{"name":"observers.verdicts"},{"name":"attention.list"},{"name":"applications.list"},{"name":"server.card"}]}'
      exit 0
    fi
    [ "$1 $2" = "monitor stream" ] || exit 2
    echo "fake topo started" >&2
    seq=0
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')
      case "$id" in *crash*) exit 3;; esac
      seq=$((seq+1))
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      printf '{"schema":1,"name":"stream","request_id":"%s","instance":"fake-%s","sequence":%d,"lifecycle":"running","generated_at":"%s","publisher_expires_at":"%s","rows":[]}\n' "$id" "$$" "$seq" "$now" "$now"
    done
    printf '{"schema":1,"name":"stream","lifecycle":"stopped","rows":[]}\n'
    exit 0
    """#

    static let old = "#!/bin/sh\necho 'topo: invalid monitor name' >&2\nexit 1\n"

    static func install(_ body: String = script) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appending(path: "fake-topo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appending(path: "topo").path
        try body.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }
}

func config(_ path: String, backoff: TimeInterval = 0.2) -> ProcessEngine.Configuration {
    var c = ProcessEngine.Configuration(topoPath: path, shellPath: { "" })
    c.minimumBackoff = backoff
    c.unavailableRetry = 0.5
    return c
}

@Suite(.serialized) struct ProcessEngineTests {
    @Test func runsUpdatesAndStops() async throws {
        let path = try FakeTopo.install()
        let engine = ProcessEngine(configuration: config(path))
        let rec = Recorder(engine.start(request("settings-1")))
        #expect(await rec.wait { frames($0).contains { $0.requestID == "settings-1" } })
        guard case .running(let r)? = rec.statuses.first(where: \.isRunning) else { Issue.record("not running"); return }
        #expect(r.pid > 0)
        #expect(r.path == path)
        #expect(r.version == "9.9.9-fake")
        #expect(await rec.wait { $0.contains { if case .diagnostic("fake topo started") = $0 { true } else { false } } })

        try await engine.update(request("settings-2"))
        #expect(await rec.wait { frames($0).contains { $0.requestID == "settings-2" } })

        await engine.stop()
        await rec.finished()
        #expect(rec.frames.last?.lifecycle == .stopped)
        #expect(rec.statuses.last == .stopped)
        #expect(!rec.statuses.contains { if case .restarting = $0 { true } else { false } })
    }

    @Test func restartsWithBackoff() async throws {
        let path = try FakeTopo.install()
        let engine = ProcessEngine(configuration: config(path, backoff: 0.2))
        let rec = Recorder(engine.start(request("crash-1")))
        let restarts: @Sendable ([EngineEvent]) -> [TimeInterval] = { events in
            events.compactMap { if case .status(.restarting(let d, _, _)) = $0 { d } else { nil } }
        }
        #expect(await rec.wait { restarts($0).count >= 2 })
        #expect(Array(restarts(rec.all).prefix(2)) == [0.2, 0.4])
        // The next process gets the latest request.
        try await engine.update(request("settings-ok"))
        #expect(await rec.wait { frames($0).contains { $0.requestID == "settings-ok" } })
        await engine.stop()
        await rec.finished()
        #expect(rec.statuses.last == .stopped)
    }

    @Test func saysWhenTopoIsTooOld() async throws {
        let path = try FakeTopo.install(FakeTopo.old)
        let engine = ProcessEngine(configuration: config(path))
        let rec = Recorder(engine.start(request()))
        #expect(await rec.wait { $0.contains { if case .status(.unavailable(.upgradeNeeded(path))) = $0 { true } else { false } } })
        await engine.stop()
        await rec.finished()
    }

    @Test(.enabled(if: !TopoLocator.fallbacks.contains { FileManager.default.isExecutableFile(atPath: $0 + "/topo") }))
    func saysWhenTopoIsMissing() async throws {
        let engine = ProcessEngine(configuration: config("/nonexistent/topo"))
        let rec = Recorder(engine.start(request()))
        #expect(await rec.wait { $0.contains { if case .status(.unavailable(.notFound)) = $0 { true } else { false } } })
        guard case .unavailable(.notFound(let searched))? = rec.statuses.last else { Issue.record("not missing"); return }
        #expect(searched.first == "/nonexistent/topo")
        #expect(searched.contains("/opt/homebrew/bin/topo"))
        #expect(searched.contains("/usr/local/bin/topo"))
        await engine.stop()
        await rec.finished()
    }
}

@Suite struct TopoLocatorTests {
    @Test func searchOrder() throws {
        let a = try FakeTopo.install()
        let b = try FakeTopo.install()
        let dirA = (a as NSString).deletingLastPathComponent
        let dirB = (b as NSString).deletingLastPathComponent
        #expect(try TopoLocator(setting: a, shellPath: { dirB }).locate().get() == .init(path: a, origin: "setting"))
        #expect(try TopoLocator(setting: "", shellPath: { "/nope:\(dirB):\(dirA)" }).locate().get() == .init(path: b, origin: "PATH"))
        #expect(try TopoLocator(setting: "/missing/topo", shellPath: { dirA }).locate().get() == .init(path: a, origin: "PATH"))
    }

    @Test func readsTheLoginShellPATH() {
        let path = TopoLocator.loginShellPATH()
        #expect(path?.contains("/usr/bin") == true)
    }
}

/// Runs only when `TOPO_BIN` points at a `topo` with `monitor stream`
/// protocol 1, against its synthetic preview source.
@Suite(.serialized, .enabled(if: Integration.topo != nil)) struct IntegrationTests {
    func preview(_ id: String, scenario: Int = 0, limit: Int = 3) -> Request {
        var s = Settings()
        s.topo.source = "preview"
        s.topo.scenario = scenario
        s.sections.attentionLimit = limit
        var r = TemplateCompiler().request(for: s, revision: 1)
        r.requestID = id
        return r
    }

    @Test func capabilities() throws {
        let caps = try ProcessEngine.check(Integration.topo!).get()
        #expect(caps.protocol == 1 || caps.protocols.contains(1))
        #expect(caps.sources.contains("preview"))
        #expect(caps.missing().isEmpty)
    }

    @Test func streamsThePreviewNetwork() async throws {
        let engine = ProcessEngine(configuration: config(Integration.topo!))
        let rec = Recorder(engine.start(preview("it-1")))
        #expect(await rec.wait(timeout: 20) { frames($0).contains { $0.requestID == "it-1" && $0.lifecycle == .running } })
        let f = try #require(rec.frames.last { $0.requestID == "it-1" })
        var p = ReaderPolicy()
        p.receive(f, at: Date())
        let r = p.evaluate(at: Date())
        #expect(r.isLive)
        guard case .verdict(let v) = r.row("status")?.value else { Issue.record("no verdict: \(f.rows)"); return }
        if let c = v.counts?.health.complete { #expect(v.configured == c.up + c.warning + c.down + c.unknown) }
        #expect(r.row("seen")?.isCurrent == true)
        #expect(r.row("attention")?.isCurrent == true)
        #expect(r.row("apps")?.isCurrent == true)

        // Another scenario, applied without a restart.
        try await engine.update(preview("it-2", scenario: 1, limit: 5))
        #expect(await rec.wait(timeout: 20) { frames($0).contains { $0.requestID == "it-2" } })
        // A refused line leaves the previous request running. The compiler
        // never writes a limit over 20, so set it by hand.
        var refused = preview("it-3")
        refused.template.rows = refused.template.rows.map { var r = $0; if r.metric == "attention.list" { r.limit = 99 }; return r }
        try await engine.update(refused)
        #expect(await rec.wait(timeout: 20) { frames($0).contains { $0.requestID == "it-3" && $0.lifecycle == .error } })
        let afterRefusal = rec.frames.count
        #expect(await rec.wait(timeout: 20) { frames($0).dropFirst(afterRefusal).contains { $0.requestID == "it-2" && $0.lifecycle == .running } })

        await engine.stop()
        await rec.finished()
        #expect(rec.frames.last?.lifecycle == .stopped)
        #expect(!rec.statuses.contains { if case .restarting = $0 { true } else { false } })
    }
}

/// Every preview scenario, in every language, with every section and a
/// node that doesn't exist: each row decodes to its metric's shape.
@Suite(.serialized, .enabled(if: Integration.topo != nil)) struct PreviewScenarioTests {
    @Test func everyScenarioDecodes() async throws {
        var s = Settings()
        s.topo.source = "preview"
        s.sections.setEnabled(.servers, true)
        s.sections.serverNodes = ["relay", "app", "jp-openlist", "no-such-node"]
        s.sections.mac.mode = .server
        s.sections.mac.node = "mac"
        let engine = ProcessEngine(configuration: config(Integration.topo!))
        var first = TemplateCompiler().request(for: s, revision: 0)
        first.requestID = "scenario-start"
        let rec = Recorder(engine.start(first))
        for lang in ["en", "ja", "zh"] {
            for scenario in 0...17 {
                s.topo.scenario = scenario
                let id = "scenario-\(lang)-\(scenario)"
                var r = TemplateCompiler().request(for: s, revision: 0, lang: lang)
                r.requestID = id
                try await engine.update(r)
                let got = await rec.wait(timeout: 20) { frames($0).contains { $0.requestID == id } }
                #expect(got, "\(id): no frame")
                guard let f = rec.frames.last(where: { $0.requestID == id }) else { continue }
                #expect(f.lifecycle == .running, "\(id): \(f.lifecycle) \(String(describing: f.error))")
                for row in f.rows {
                    switch row.value {
                    case .malformed, .other: Issue.record("\(id) \(row.id) \(row.metric): \(row.value)")
                    default: break
                    }
                    if row.id == TemplateCompiler.RowID.server(3) {
                        // An unreachable collector (13) can't say which nodes exist.
                        let reason = scenario == 13 ? "source_unavailable" : "entity_missing"
                        #expect(row.value == .none && row.reason == reason, "\(id): \(row.reason)")
                    } else if row.value == .none {
                        #expect(!row.reason.isEmpty, "\(id) \(row.id): empty with no reason")
                    }
                }
            }
        }
        await engine.stop()
        await rec.finished()
    }
}

enum Integration {
    static let topo: String? = {
        guard let p = ProcessInfo.processInfo.environment["TOPO_BIN"], !p.isEmpty,
              case .success = ProcessEngine.check(p) else { return nil }
        return p
    }()
}
