import Foundation
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
