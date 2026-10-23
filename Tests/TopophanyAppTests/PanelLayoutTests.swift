import AppKit
import Foundation
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanyThemes

@MainActor
@Suite(.serialized) struct PanelLayoutTests {
    @Test func geometryOwnsWindowSizeAndRefreshesNeverForceMeasurement() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appending(path: "panel-layout-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appending(path: "settings.json"))
        var settings = Settings()
        settings.openAtLogin = false
        settings.appearance.panelHeight = 720
        settings.sections.mac.mode = .off
        settings.sections.attentionLimit = 5
        try store.save(settings)
        let model = AppModel(store: store)
        let now = Date()
        var frame = try #require(FrameDecoder.frame(from: FixtureEngine.lines(.incidents)[0]))
        frame.generatedAt = now
        frame.publisherExpiresAt = now.addingTimeInterval(300)
        for index in frame.rows.indices {
            frame.rows[index].validUntil = now.addingTimeInterval(300)
            frame.rows[index].sampledAt = now
        }
        model.handle(.frame(frame, line: Data()))
        let controller = PanelController(model: model)
        model.onChange = { [weak controller] in controller?.update() }
        // A deterministic anchor avoids the menu bar server moving a newly
        // registered status item while this test measures the panel's top.
        let screen = try #require(NSScreen.main)
        let anchor = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 22,
                                                  width: 24, height: 22),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        anchor.isReleasedWhenClosed = false
        defer { anchor.close() }
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        anchor.contentView = button
        defer {
            controller.close()
            controller.window?.orderOut(nil)
        }

        func checkBounds() async throws -> NSWindow {
            // Includes the opening animation's completion, which must not
            // restore a stale or zero-size frame after geometry has settled.
            try await Task.sleep(for: .milliseconds(350))
            let window = try #require(controller.window)
            let content = try #require(window.contentView)
            #expect(window.frame.width > 200 && window.frame.height > 100)
            #expect(content.frame.size == window.frame.size)
            #expect(content.bounds.size == window.frame.size)
            return window
        }

        controller.open(from: button)
        let window = try await checkBounds()
        let top = window.frame.maxY
        let nativeWidth = window.frame.width
        model.update { $0.appearance.panelHeight = 640 }
        _ = try await checkBounds()
        #expect(abs(window.frame.maxY - top) < 1)
        model.update { $0.appearance.theme = "terminal" }
        _ = try await checkBounds()
        #expect(window.frame.width != nativeWidth)

        PanelDiagnostics.start()
        for second in 1...30 { model.refresh(at: now.addingTimeInterval(Double(second))) }
        let data = Data(PanelDiagnostics.stop().utf8)
        let counters = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(counters["panel.measure"] == nil)
        _ = try await checkBounds()

        controller.close()
        try await Task.sleep(for: .milliseconds(200))
        controller.open(from: button)
        _ = try await checkBounds()
    }
}
