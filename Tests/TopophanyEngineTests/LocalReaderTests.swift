import Foundation
import Synchronization
import Testing
import TopophanyKit
@testable import TopophanyEngine

/// The proxy engine on this Mac, read by a second `topo` stream. Every
/// reply here is synthetic: no `topo`, engine or network is involved.
private let localNow = Date(timeIntervalSince1970: 1_793_520_000)

/// A value the fakes' `@Sendable` closures share.
private final class Shared<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ v: T) { stored = v }
    var value: T { lock.withLock { stored } }
    func with<R>(_ f: (inout T) -> R) -> R { lock.withLock { f(&stored) } }
}

@MainActor @Suite struct LocalReaderTests {
    final class FakeEngine: Engine, Sendable {
        private let state = Mutex<(requests: [Request], continuation: AsyncStream<EngineEvent>.Continuation?, stopped: Bool)>(([], nil, false))
        var requests: [Request] { state.withLock { $0.requests } }
        var stopped: Bool { state.withLock { $0.stopped } }
        func start(_ request: Request) -> AsyncStream<EngineEvent> {
            AsyncStream { c in state.withLock { $0.requests.append(request); $0.continuation = c } }
        }
        func update(_ request: Request) async throws { state.withLock { $0.requests.append(request) } }
        func stop() async { state.withLock { $0.stopped = true; $0.continuation?.finish() } }
        func send(_ event: EngineEvent) { _ = state.withLock { $0.continuation?.yield(event) } }
    }

    nonisolated static var now: Date { localNow }
    struct Clock: WallClock { func now() -> Date { localNow } }

    nonisolated static func check(_ id: String, mode: String = "rule") -> [String: Any] {
        ["id": id, "name": "Proxy engine", "adapter": "mihomo", "url": "http://127.0.0.1:19090", "interval_seconds": 30,
         "timeout_seconds": 5, "stale_seconds": 90, "root_proxy": "Proxy", "expected_mode": mode, "expected_tun": NSNull()]
    }

    /// `topo local list`'s reply for `checks`, as bytes.
    nonisolated static func listed(_ checks: [[String: Any]], revision: String, auth: String = "token") -> Data {
        let entries = checks.map { ["check": $0, "auth_mode": auth] as [String: Any] }
        let body: [String: Any] = ["schema": 1, "request_id": "", "ok": true, "data": ["profile_revision": revision, "checks": entries]]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    nonisolated fileprivate static func client(_ lists: Shared<Int>, checks: [[String: Any]], revision: String = "rev-1") -> LocalClient {
        let reply = listed(checks, revision: revision)
        return LocalClient { command, data in
            #expect(command == .list && data == nil)
            lists.with { $0 += 1 }
            return .init(status: 0, stdout: reply)
        }
    }

    nonisolated static func frame(_ requestID: String, check id: String, lifecycle: String = "running", error: String? = nil) throws -> (Frame, Data) {
        let stamp = { (d: Date) in ISO8601DateFormatter().string(from: d) }
        var f: [String: Any] = [
            "schema": 1, "name": "stream", "request_id": requestID, "config_revision": "local-1", "instance": "local", "sequence": 1,
            "source": "local", "project": "local", "lifecycle": lifecycle, "generated_at": stamp(now),
            "publisher_expires_at": stamp(now.addingTimeInterval(60)), "title": "Topophany", "bar_row": "local-1",
        ]
        if let error {
            f["error"] = ["code": error, "message": "synthetic"]
            f["rows"] = [] as [Any]
        } else {
            let check: [String: Any] = [
                "id": id, "name": "Proxy engine", "kind": "mihomo", "endpoint": "", "health": "up", "freshness": "fresh",
                "sampled_at": stamp(now.addingTimeInterval(-2)), "valid_until": stamp(now.addingTimeInterval(88)),
                "samples": ["interval_seconds": 30, "slots": [["outcome": "ok", "elapsed_ms": 4]]],
                "observer": ["id": "local", "name": "This machine"], "reason": "",
                "diagnostic": ["outcome": "ok", "evidence": "reported", "stage": "adapter", "code": "", "policy": "matched",
                               "facts": ["mode": "rule", "tun_enabled": "false"], "expected": ["mode": "rule"]],
            ]
            f["rows"] = [["id": "local-1", "label": "", "metric": "check.card", "select": ["check": id], "visual": "card", "text": "",
                          "health": "up", "freshness": "fresh", "sampled_at": stamp(now.addingTimeInterval(-2)),
                          "valid_until": stamp(now.addingTimeInterval(88)), "value": check]]
        }
        let line = try JSONSerialization.data(withJSONObject: f)
        return (try #require(FrameDecoder.frame(from: line)), line)
    }

    func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func followsTheSavedChecksInTheirOwnStream() async throws {
        let lists = Shared(0), engine = FakeEngine()
        var made: [String] = []
        let reader = LocalReader(clock: Clock(), makeClient: { _ in Self.client(lists, checks: [Self.check("lc-a")]) },
                                 makeEngine: { path in made.append(path); return engine })
        var changes = 0
        reader.onChange = { changes += 1 }
        #expect(reader.evaluate(at: Self.now) == nil)
        reader.attach(path: "/synthetic/topo")
        try await settle { !engine.requests.isEmpty }
        #expect(made == ["/synthetic/topo"] && reader.pins == [MonitorPin(kind: .check, id: "lc-a")])
        let request = try #require(engine.requests.first)
        #expect(request.source == "local" && request.profile.isEmpty && request.credentials.isEmpty && request.profileRevision == "rev-1")
        #expect(request.template.rows.map(\.metric) == ["check.card"] && request.template.rows.first?.select?.check == "lc-a")
        #expect(request.template.rows.first?.history == true && request.template.bar.row == "local-1")

        // Another request's frame, or another source's, is not this one.
        let (stale, staleLine) = try Self.frame("local-0", check: "lc-a")
        engine.send(.frame(stale, line: staleLine))
        let (f, line) = try Self.frame(request.requestID, check: "lc-a")
        engine.send(.status(.running(.init(pid: 1, path: "/synthetic/topo", version: "dev", startedAt: Self.now))))
        engine.send(.frame(f, line: line))
        try await settle { reader.evaluate(at: Self.now)?.rows.isEmpty == false }
        let reading = try #require(reader.evaluate(at: Self.now))
        #expect(reading.rows.count == 1 && reading.frame?.requestID == request.requestID)
        #expect(changes > 0 && reader.problem == nil)

        // The same topo again lists afresh and updates the running stream.
        reader.attach(path: "/synthetic/topo")
        try await settle { engine.requests.count == 2 }
        #expect(made.count == 1 && lists.value == 2)

        reader.stop()
        try await settle { engine.stopped }
        #expect(engine.stopped && reader.evaluate(at: Self.now) == nil && reader.path == nil)
    }

    @Test func nothingSetUpRunsNoStreamAndAConflictListsAgain() async throws {
        let lists = Shared(0), engine = FakeEngine()
        let reply = Shared(Self.listed([], revision: "rev-0", auth: "none"))
        let reader = LocalReader(clock: Clock(), makeClient: { _ in
            LocalClient { _, _ in
                lists.with { $0 += 1 }
                return .init(status: 0, stdout: reply.value)
            }
        }, makeEngine: { _ in engine })
        reader.attach(path: "/synthetic/topo")
        try await settle { lists.value == 1 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(engine.requests.isEmpty && reader.evaluate(at: Self.now) == nil)

        reply.with { $0 = Self.listed([Self.check("lc-b")], revision: "rev-1", auth: "none") }
        reader.reload()
        try await settle { !engine.requests.isEmpty }
        let id = try #require(engine.requests.first?.requestID)
        // Saved elsewhere since: topo refuses the old revision, and the reader lists again.
        let (f, line) = try Self.frame(id, check: "lc-b", lifecycle: "error", error: "profile_conflict")
        engine.send(.frame(f, line: line))
        try await settle { lists.value == 3 }
        #expect(lists.value == 3)
        reader.closeNow()
        try await settle { engine.stopped }
        #expect(engine.stopped)
    }

    @Test func editorKeepsItsSecretToOneCommand() async throws {
        let seen = Shared<[[String: Any]]>([])
        let client = LocalClient { command, data in
            let input = try JSONSerialization.jsonObject(with: data!) as! [String: Any]
            seen.with { $0.append(input) }
            let id = input["request_id"] as! String
            let check = input["check"] as! [String: Any]
            let payload: [String: Any] = command == .inspect
                ? ["check": check, "engine": ["version": "v1.19.0", "mode": "rule", "tun": false],
                   "groups": [["name": "Proxy", "type": "Selector"], ["name": "Auto", "type": "URLTest"]], "truncated": false, "warnings": []]
                : ["profile_revision": "rev-2", "check_id": check["id"]!]
            return .init(status: 0, stdout: try JSONSerialization.data(withJSONObject: ["schema": 1, "request_id": id, "ok": true, "data": payload]))
        }
        let editor = LocalEditor(client: client, revision: "rev-1", name: "Proxy engine")
        #expect(editor.isNew && editor.secrets == [.token, .none] && editor.check.url == LocalCheck.defaultURL)
        editor.check.url = "http://192.0.2.1:9090"
        #expect(!editor.urlIsLocal)
        editor.inspect()
        #expect(editor.problem == "not_local_address" && seen.value.isEmpty)

        editor.check.url = "http://127.0.0.1:19090"; editor.changed()
        editor.token = "synthetic-secret"; editor.check.rootProxy = "Gone"
        editor.inspect()
        try await settle { !editor.busy }
        #expect(editor.inspection?.groups.map(\.name) == ["Proxy", "Auto"] && editor.canSave)
        // A group the engine no longer has isn't followed.
        #expect(editor.check.rootProxy.isEmpty)
        editor.check.rootProxy = "Proxy"; editor.check.expectedMode = "rule"
        var saved: LocalChanged?
        editor.onSaved = { saved = $0 }
        editor.save()
        try await settle { saved != nil }
        #expect(saved?.profileRevision == "rev-2" && editor.token.isEmpty)
        let save = try #require(seen.value.last)
        #expect(save["base_revision"] as? String == "rev-1")
        #expect((save["auth"] as? [String: String]) == ["mode": "token", "token": "synthetic-secret"])
        let check = try #require(save["check"] as? [String: Any])
        #expect(check["root_proxy"] as? String == "Proxy" && check["expected_tun"] is NSNull)

        // Editing a saved check: its saved secret is for its saved address only.
        let entry = try JSONDecoder().decode(LocalChecks.Entry.self, from: JSONSerialization.data(withJSONObject: ["check": check, "auth_mode": "token"]))
        let again = LocalEditor(client: client, revision: "rev-2", entry: entry)
        #expect(again.secret == .saved && again.secrets.first == .saved)
        again.check.url = "http://127.0.0.1:9097"
        again.inspect()
        #expect(again.problem == "saved_auth_mismatch")
        again.close()
    }
}
