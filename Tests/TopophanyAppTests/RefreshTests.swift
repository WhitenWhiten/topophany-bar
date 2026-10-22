import Foundation
import Synchronization
import Testing
import TopophanyEngine
import TopophanyKit

@MainActor
@Suite struct RefreshTests {
    func model() -> AppModel {
        let url = FileManager.default.temporaryDirectory.appending(path: "refresh-tests-\(UUID().uuidString).json")
        return AppModel(store: SettingsStore(url: url))
    }

    @Test func hiddenPanelStaysIdleWhileEvidenceExpires() throws {
        let m = model()
        let now = Date()
        var f = try #require(FrameDecoder.frame(from: FixtureEngine.lines(.incidents)[0]))
        f.generatedAt = now
        f.publisherExpiresAt = now.addingTimeInterval(10)
        for i in f.rows.indices { f.rows[i].validUntil = now.addingTimeInterval(2); f.rows[i].sampledAt = now }
        m.handle(.frame(f, line: Data()))
        #expect(!m.status.isBlind)
        let frozen = m.panel
        m.refresh(at: now.addingTimeInterval(3))
        #expect(m.status.isBlind)
        #expect(m.statusItem.activity == .resting)
        #expect(m.panel == frozen)
        // Opening refreshes the full panel immediately.
        m.setPanelVisible(true)
        #expect(!m.panel.status.isBlind)
        m.setPanelVisible(false)
        let closed = m.panel
        m.refresh(at: now.addingTimeInterval(11))
        #expect(m.panel == closed)
        #expect(m.status.isBlind)
    }

    @Test func settingsKeepTheirModelsCurrentAndDiagnosticsDoNotRefresh() {
        let m = model()
        m.setSettingsVisible(true)
        let now = Date().addingTimeInterval(5)
        m.refresh(at: now)
        #expect(m.panel.status.now == now)
        let unchanged = m.panel
        let buffer = EngineDiagnostics()
        for i in 0..<1000 { _ = buffer.append("line \(i)") }
        m.handle(.diagnostics(buffer))
        #expect(m.panel == unchanged)
        #expect(m.diagnostics.count == 50)
        m.setSettingsVisible(false)
        m.refresh(at: now.addingTimeInterval(1))
        #expect(m.panel == unchanged)
    }
}

private final class RecordingEngine: Engine, Sendable {
    private let requests = Synchronization.Mutex<[Request]>([])
    var all: [Request] { requests.withLock { $0 } }
    func start(_ request: Request) -> AsyncStream<EngineEvent> {
        requests.withLock { $0.append(request) }
        return AsyncStream { _ in }
    }
    func update(_ request: Request) async throws { requests.withLock { $0.append(request) } }
    func stop() async {}
}

extension RefreshTests {
    @Test func directRequestsAndRapidSwitchingStayInOneProcess() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "app-direct-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appending(path: "settings.json"))
        var settings = Settings(); settings.topo.source = "direct"; settings.topo.profile = "A"
        settings.sections.mac.mode = .off
        try store.save(settings)
        let clock = ManualClock(Timestamp.parse("2026-10-21T12:00:00Z")!)
        let engine = RecordingEngine()
        var starts = 0
        let model = AppModel(store: store, clock: clock, directRoot: root.appending(path: "direct").path,
                             engineFactory: { _ in starts += 1; return engine })
        model.restartEngine()
        let first = try #require(engine.all.first)
        func frame(_ request: Request, dataset: String, sequence: UInt64) -> Frame {
            var f = Frame(requestID: request.requestID, instance: "test", sequence: sequence, source: "direct",
                          generatedAt: clock.now(), publisherExpiresAt: clock.now().addingTimeInterval(30), rows: [])
            f.profile = request.profile; f.datasetID = dataset
            return f
        }
        model.handle(.frame(frame(first, dataset: "dataset-A", sequence: 1), line: Data()))
        model.update { $0.topo.profile = "B" }
        for _ in 0..<10 { await Task.yield() }
        let second = try #require(engine.all.last)
        model.update { $0.topo.profile = "A" }
        for _ in 0..<10 { await Task.yield() }
        let third = try #require(engine.all.last)
        model.handle(.frame(frame(second, dataset: "dataset-B", sequence: 2), line: Data()))
        #expect(model.reading.frame == nil)
        model.handle(.frame(frame(third, dataset: "dataset-A", sequence: 3), line: Data()))
        #expect(model.reading.frame?.datasetID == "dataset-A")
        model.update { $0.language = .ja; $0.topo.interval = "1s"; $0.sections.serverNodes = ["bs-source.object"] }
        for _ in 0..<10 { await Task.yield() }
        #expect(starts == 1)
        #expect(engine.all.last?.source == "direct")
        #expect(engine.all.last?.retryNonce == nil)
        model.stopNow()
    }
    @Test func isolatedDirectNeverEnumeratesClientCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "app-direct-isolation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = root.appending(path: "profiles-was-called")
        let binary = root.appending(path: "synthetic-topo")
        try ("#!/bin/sh\ntouch '" + marker.path + "'\necho '{\"schema\":1,\"profiles\":[]}'\n").write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let store = SettingsStore(url: root.appending(path: "settings.json"))
        var settings = Settings(); settings.topo.source = "direct"; settings.topo.profile = "A"; settings.sections.mac.mode = .off
        try store.save(settings)
        let engine = RecordingEngine()
        let model = AppModel(store: store, directRoot: root.appending(path: "direct").path, engineFactory: { _ in engine })
        model.restartEngine()
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"sources":["client","direct"],"profiles":true}"#.utf8))
        model.handle(.capabilities(caps))
        model.handle(.status(.running(.init(pid: 0, path: binary.path, version: "synthetic", startedAt: Date()))))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        model.selectSource("client")
        #expect(engine.all.last?.source == "client")
        #expect(engine.all.last?.credentials == root.appending(path: "direct/client-credentials.json").path)
        model.handle(.capabilities(caps))
        model.handle(.status(.running(.init(pid: 0, path: binary.path, version: "synthetic", startedAt: Date()))))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        model.stopNow()
    }

}
