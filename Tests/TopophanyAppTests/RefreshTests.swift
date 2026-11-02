import Foundation
import Synchronization
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanyWidgets

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
    @Test func openingExpiredCollectorShowsAcquisitionUntilReadCompletes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "open-expired-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appending(path: "settings.json"))
        var settings = Settings(); settings.topo.source = "client"; settings.topo.profile = "S2"; settings.sections.mac.mode = .off
        try store.save(settings)
        let clock = ManualClock(Timestamp.parse("2026-11-01T10:00:00Z")!)
        let engine = RecordingEngine()
        let m = AppModel(store: store, clock: clock, engineFactory: { _ in engine })
        m.restartEngine()
        defer { m.stopNow() }
        m.handle(.capabilities(try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"sources":["client"],"client_retry":true,"collector_read":true}"#.utf8))))
        m.handle(.status(.running(.init(pid: 0, path: "fixture", version: "test", startedAt: clock.now()))))
        var f = try #require(FrameDecoder.frame(from: FixtureEngine.lines(.clear)[0]))
        f.source = "client"; f.requestID = try #require(engine.all.first?.requestID); f.instance = "open-test"; f.sequence = 1
        f.generatedAt = clock.now(); f.publisherExpiresAt = clock.now().addingTimeInterval(30)
        for i in f.rows.indices { f.rows[i].validUntil = clock.now().addingTimeInterval(2); f.rows[i].sampledAt = clock.now() }
        f.collectorRead = try JSONDecoder().decode(CollectorRead.self, from: Data(#"{"state":"ok","completed_at":"2026-11-01T10:00:00Z","last_success_at":"2026-11-01T10:00:00Z"}"#.utf8))
        m.handle(.frame(f, line: Data()))
        clock.advance(3)
        m.setPanelVisible(true)
        #expect(m.panel.status.isBlind && m.panel.status.counts == nil)
        #expect(m.panel.status.collector?.refreshing == true)
        #expect(m.panel.status.isAwaitingCollector)
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.all.count == 2)

        // A retry acknowledgment carries the old evidence. It cannot end the
        // acquisition state or restore withheld verdicts.
        f.requestID = try #require(engine.all.last?.requestID); f.sequence = 2
        m.handle(.frame(f, line: Data()))
        #expect(m.panel.status.isAwaitingCollector && m.panel.status.counts == nil)
        f.sequence = 3; f.generatedAt = clock.now()
        for i in f.rows.indices { f.rows[i].validUntil = clock.now().addingTimeInterval(2); f.rows[i].sampledAt = clock.now() }
        f.collectorRead?.completedAt = clock.now(); f.collectorRead?.lastSuccessAt = clock.now()
        m.handle(.frame(f, line: Data()))
        #expect(!m.panel.status.isBlind && !m.refreshingCollector)

        m.setPanelVisible(false)
        clock.advance(6)
        m.setPanelVisible(true)
        #expect(m.panel.status.isAwaitingCollector)
        clock.advance(10)
        m.refresh()
        #expect(m.panel.status.isBlind && !m.panel.status.isAwaitingCollector)
        #expect(!m.refreshingCollector, "an unanswered retry must return to the actual expiry state")
    }

    @Test func historyDemandSurvivesDisclosureAndPinsStayScoped() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "history-demand-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appending(path: "settings.json"))
        let pin = MonitorPin(kind: .check, id: "runtime")
        var settings = Settings(); settings.topo.source = "client"; settings.topo.profile = "S2"
        settings.sections.monitors = [pin]; settings.sections.services = true; settings.sections.mac.mode = .off
        try store.save(settings)
        let engine = RecordingEngine()
        let m = AppModel(store: store, engineFactory: { _ in engine })
        m.restartEngine()
        defer { m.stopNow() }
        #expect(engine.all[0].template.rows.first { $0.metric == pin.metric }?.history == false)
        m.handle(.capabilities(try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"card_history":true}"#.utf8))))
        m.toggleMonitor(pin)
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.all.count == 2)
        #expect(engine.all[1].template.rows.first { $0.metric == pin.metric }?.history == true)
        m.toggleMonitor(pin); m.toggleMonitor(pin)
        m.setPanelVisible(false); m.setPanelVisible(true)
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.all.count == 2, "disclosure/reopening replaced the source")
        m.update { $0.topo.profile = "Other" }
        #expect(m.settings.sections.monitors.isEmpty)
        m.update { $0.topo.profile = "S2" }
        #expect(m.settings.sections.monitors == [pin])
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.all.last?.template.rows.first { $0.metric == pin.metric }?.history == false)
    }

    @Test func clientRetryWaitsForAcquisitionAndKeepsOneEngine() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "client-retry-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appending(path: "settings.json"))
        var settings = Settings(); settings.topo.source = "client"; settings.topo.profile = "S2"; settings.sections.mac.mode = .off
        try store.save(settings)
        let clock = ManualClock(Timestamp.parse("2026-11-01T10:00:00Z")!)
        let engine = RecordingEngine()
        var starts = 0
        let m = AppModel(store: store, clock: clock, engineFactory: { _ in starts += 1; return engine })
        m.restartEngine()
        defer { m.stopNow() }
        m.handle(.capabilities(try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"sources":["client"],"client_retry":true,"collector_read":true}"#.utf8))))
        m.handle(.status(.running(.init(pid: 0, path: "fixture", version: "test", startedAt: clock.now()))))
        var f = try #require(FrameDecoder.frame(from: FixtureEngine.lines(.clear)[0]))
        f.source = "client"; f.requestID = try #require(engine.all.first?.requestID); f.instance = "collector-test"; f.sequence = 1
        f.generatedAt = clock.now(); f.publisherExpiresAt = clock.now().addingTimeInterval(30)
        for i in f.rows.indices { f.rows[i].validUntil = clock.now().addingTimeInterval(20); f.rows[i].sampledAt = clock.now() }
        f.collectorRead = try JSONDecoder().decode(CollectorRead.self, from: Data(#"{"state":"ok","completed_at":"2026-11-01T10:00:00Z","last_success_at":"2026-11-01T10:00:00Z"}"#.utf8))
        m.handle(.frame(f, line: Data()))
        m.setPanelVisible(true)
        #expect(engine.all.count == 1, "fresh panel must not refetch")
        m.retryCollector(); m.retryCollector()
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.all.count == 2 && starts == 1)
        #expect(m.applyingRequestID == nil && m.refreshingCollector)
        let retry = try #require(engine.all.last)
        #expect(retry.retryNonce != nil && retry.template == engine.all[0].template)
        f.requestID = retry.requestID; f.sequence = 2
        m.handle(.frame(f, line: Data())) // acknowledgment with old clocks
        #expect(m.refreshingCollector)
        clock.advance(1); f.sequence = 3
        f.collectorRead?.completedAt = clock.now(); f.collectorRead?.lastSuccessAt = clock.now()
        m.handle(.frame(f, line: Data()))
        #expect(!m.refreshingCollector)
        m.retryCollector()
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.all.count == 2, "five-second cooldown")
        clock.advance(5)
        m.retryCollector()
        for _ in 0..<10 { await Task.yield() }
        let nextRetry = try #require(engine.all.last)
        // A read already in flight can complete before the retry acknowledgment.
        f.sequence = 4; f.collectorRead?.completedAt = clock.now()
        m.handle(.frame(f, line: Data()))
        #expect(!m.refreshingCollector)
        f.sequence = 5; f.requestID = nextRetry.requestID
        m.handle(.frame(f, line: Data()))
        #expect(m.activeRequestID == nextRetry.requestID)
        // Switching profile cannot carry last-known health across datasets.
        m.update { $0.topo.profile = "Other" }
        for _ in 0..<10 { await Task.yield() }
        f.requestID = try #require(engine.all.last?.requestID); f.sequence = 6
        for i in f.rows.indices { f.rows[i].value = .none; f.rows[i].reason = "source_unavailable" }
        m.handle(.frame(f, line: Data()))
        #expect(m.reading.lastKnown == nil && m.reading.lastValues.isEmpty)
        clock.advance(5); m.retryCollector()
        for _ in 0..<10 { await Task.yield() }
        let recovery = try #require(engine.all.last)
        m.handle(.sourceEnded)
        #expect(!m.refreshingCollector)
        // A supervisor may restart with the retry that was written before
        // stdout closed. Its request ID must still be accepted.
        f.requestID = recovery.requestID; f.sequence = 7
        m.handle(.frame(f, line: Data()))
        #expect(m.activeRequestID == recovery.requestID)
        m.update { $0.topo.profile = "Missing" }
        for _ in 0..<10 { await Task.yield() }
        let rejected = try #require(engine.all.last)
        m.handle(.frame(Frame(requestID: rejected.requestID, lifecycle: .error, generatedAt: nil, publisherExpiresAt: nil,
                              rows: [], error: .init(code: "profile_not_found", message: "Profile unavailable")), line: Data()))
        #expect(!m.canRefreshCollector, "a rejected scope must not refresh the previous profile")
    }

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

    /// A collector view belongs to the mode it was chosen in: direct never
    /// carries one, and each mode gets back the view it was left in.
    @Test func viewsStayScopedToTheirMode() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "app-views-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appending(path: "settings.json"))
        var settings = Settings()
        settings.topo.source = "client"; settings.topo.profile = "home"; settings.topo.observer = "home"
        settings.sections.mac.mode = .off
        try store.save(settings)
        let engine = RecordingEngine()
        let model = AppModel(store: store, clock: ManualClock(Timestamp.parse("2026-10-21T12:00:00Z")!),
                             directRoot: root.appending(path: "direct").path, engineFactory: { _ in engine })
        model.restartEngine()
        #expect(engine.all.last?.observer == "home")
        model.selectSource("direct")
        #expect(engine.all.last?.source == "direct")
        #expect(engine.all.last?.observer == "")
        #expect(model.settings.topo.observer.isEmpty)
        model.selectSource("preview")
        model.update { $0.topo.observer = "office" }
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.all.last?.source == "preview")
        #expect(engine.all.last?.observer == "office")
        model.selectSource("client")
        #expect(engine.all.last?.source == "client")
        #expect(engine.all.last?.observer == "home")
        model.selectSource("preview")
        #expect(engine.all.last?.observer == "office")
        model.stopNow()
    }

}

@MainActor @Suite struct MigrationPinsTests {
    @Test func directPinsAreCopiedOnlyByExplicitAction() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "migration-pins-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = SettingsStore(url: path)
        var settings = Settings()
        settings.topo.source = "client"; settings.topo.profile = "migrated"
        settings.topo.modeProfiles["direct"] = "desktop"
        settings.topo.scopedPins["direct:desktop"] = ["km.object-a", "bs.object-b"]
        settings.sections.serverNodes = ["existing"]
        try store.save(settings)
        let model = AppModel(store: store)
        #expect(model.settings.sections.serverNodes == ["existing"])
        model.useDirectPinsForMigration()
        #expect(model.settings.sections.serverNodes == ["km.object-a", "bs.object-b"])
        #expect(model.settings.topo.scopedPins["direct:desktop"] == ["km.object-a", "bs.object-b"])
    }
}

@MainActor @Suite struct InAppDemoTests {
    @Test func previewDoesNotOverwriteConnection() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "demo-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = SettingsStore(url: path)
        var settings = Settings(); settings.topo.source = "direct"; settings.topo.profile = "private-desktop"
        try store.save(settings)
        let engine = RecordingEngine()
        let model = AppModel(store: store, engineFactory: { _ in engine })
        defer { model.stopNow() }
        let widgetDirectory = FileManager.default.temporaryDirectory.appending(path: "demo-widgets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: widgetDirectory) }
        let handoffStore = HandoffStore(directory: widgetDirectory)
        model.widgets = WidgetBridge(store: handoffStore, reload: {})
        model.setDemo(true)
        for _ in 0..<100 where model.reading.frame == nil { await Task.yield() }
        #expect(model.inAppDemo)
        #expect(model.reading.frame?.source == "preview")
        #expect(model.effectiveSettings.topo.source == "preview")
        let handoff = try #require(handoffStore.read())
        #expect(handoff.decodedSettings.topo.source == "preview")
        #expect(!handoff.isDirect)
        #expect(handoff.panel().status.synthetic)
        #expect(handoff.decodedSettings.sections.serverNodes == ["oracle-ny", "bwh-la"])
        #expect(store.load().topo.profile == "private-desktop")
        model.setDemo(false)
        #expect(model.effectiveSettings.topo.source == "direct")
        #expect(model.effectiveSettings.topo.profile == "private-desktop")
        #expect(store.load() == settings)
    }
}

extension RefreshTests {
    @Test func wakeAfterLongGapExpiresEvidenceAndCoalescesRetries() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "wake-gap-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appending(path: "settings.json"))
        var settings = Settings(); settings.topo.source = "client"; settings.topo.profile = "S2"; settings.sections.mac.mode = .off
        try store.save(settings)
        let clock = ManualClock(Timestamp.parse("2026-11-01T10:00:00Z")!)
        let engine = RecordingEngine()
        var starts = 0
        let m = AppModel(store: store, clock: clock, engineFactory: { _ in starts += 1; return engine })
        m.restartEngine()
        defer { m.stopNow() }
        m.handle(.capabilities(try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"sources":["client"],"client_retry":true,"collector_read":true}"#.utf8))))
        m.handle(.status(.running(.init(pid: 0, path: "fixture", version: "test", startedAt: clock.now()))))
        var f = try #require(FrameDecoder.frame(from: FixtureEngine.lines(.clear)[0]))
        f.source = "client"; f.requestID = try #require(engine.all.first?.requestID); f.instance = "wake-test"; f.sequence = 1
        f.generatedAt = clock.now(); f.publisherExpiresAt = clock.now().addingTimeInterval(30)
        for i in f.rows.indices { f.rows[i].validUntil = clock.now().addingTimeInterval(20); f.rows[i].sampledAt = clock.now() }
        m.handle(.frame(f, line: Data()))
        m.setPanelVisible(false)
        let hidden = m.panel
        clock.advance(8 * 60 * 60)
        m.refresh(at: clock.now())
        #expect(m.status.isBlind && m.panel == hidden)
        // Exercise the same handler as the workspace wake notification, without
        // suspending the test machine or attributing new timestamps to old data.
        for _ in 0..<20 { m.retryCurrentSource() }
        for _ in 0..<10 { await Task.yield() }
        #expect(starts == 1 && engine.all.count == 2)
        #expect(m.status.isBlind)
        for _ in 0..<20 { m.setPanelVisible(true); m.setPanelVisible(false) }
        for _ in 0..<10 { await Task.yield() }
        #expect(starts == 1 && engine.all.count == 2)
    }
}
