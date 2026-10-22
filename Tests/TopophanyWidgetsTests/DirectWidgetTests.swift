import Foundation
import Testing
import TopophanyKit
import TopophanyThemes
@testable import TopophanyWidgets

struct DirectWidgetTests {
    let now = Timestamp.parse("2026-10-21T12:00:00Z")!
    func handoff() throws -> Handoff {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/DirectDevelopment/ready.json")
        let bytes = try Data(contentsOf: root)
        let f = try #require(FrameDecoder.frame(from: bytes))
        var policy = ReaderPolicy(); policy.receive(f, line: bytes, at: now)
        var settings = Settings(); settings.topo.source = "direct"
        return Handoff(policy: policy, theme: ThemeStore.native, settings: settings, engineRunning: true, at: now)
    }
    @Test func deadlinesBelongToEachWidget() throws {
        let h = try handoff()
        let node = try #require(h.decodedFrame?.rows.last?.select?.node)
        #expect(WidgetSchedule.directDeadline(h, server: nil) == now.addingTimeInterval(180))
        #expect(WidgetSchedule.directDeadline(h, server: node) == now.addingTimeInterval(170))
        let entries = WidgetSchedule.entries(h, at: now.addingTimeInterval(40), server: node)
        #expect(entries.count == 2 && entries[0].isCurrent)
        #expect(entries[0].panel.servers.first?.cpu.percent == 27.5)
        #expect(entries[1].date == now.addingTimeInterval(170))
        #expect(!entries[1].isCurrent && entries[1].panel.servers.first?.cpu.percent == nil)
        #expect(entries[1].panel.status.sources?.isCurrent == false)
        #expect(entries[1].panel.status.lastKnown == nil)
        var renewed = h; renewed.writtenAt = now.addingTimeInterval(160)
        #expect(WidgetSchedule.directDeadline(renewed, server: node) == entries[1].date)
        renewed.engineRunning = false
        #expect(!WidgetSchedule.entries(renewed, at: now.addingTimeInterval(161), server: node)[0].isCurrent)
    }
    @Test func selectionsAreScopedAndHandoffHasNoAuthentication() throws {
        let h = try handoff()
        let choice = h.selectionID(node: "bs-a.object")
        #expect(h.resolveSelection(choice) == "bs-a.object")
        #expect(h.resolveSelection("bs-a.object") == nil)
        var other = h
        other.frame = Data(String(decoding: h.frame!, as: UTF8.self).replacingOccurrences(of: "synthetic-dataset", with: "new-dataset").utf8)
        #expect(other.resolveSelection(choice) == nil)
        let encoded = String(decoding: try JSONEncoder().encode(h), as: UTF8.self)
        #expect(!encoded.contains("password") && !encoded.contains("token"))
    }
    @MainActor @Test func resourceWritesAndReloadsAreSeparate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "direct-bridge-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HandoffStore(directory: directory)
        var reloads = 0
        let bridge = WidgetBridge(store: store, reload: { reloads += 1 })
        let h = try handoff()
        var policy = ReaderPolicy()
        let first = try #require(h.decodedFrame)
        policy.receive(first, line: h.frame, at: now)
        let s = h.decodedSettings
        bridge.tick(reading: policy.evaluate(at: now), policy: policy, theme: ThemeStore.native, settings: s, at: now)
        #expect(reloads == 1)
        var next = first; next.sequence = 2
        next.generatedAt = now.addingTimeInterval(15); next.publisherExpiresAt = now.addingTimeInterval(45)
        policy.receive(next, line: Data("synthetic next safe frame".utf8), at: now.addingTimeInterval(15))
        bridge.tick(reading: policy.evaluate(at: now.addingTimeInterval(15)), policy: policy, theme: ThemeStore.native, settings: s, at: now.addingTimeInterval(15))
        #expect(store.read()?.writtenAt == now.addingTimeInterval(15))
        #expect(reloads == 1)
        next.sequence = 3; next.generatedAt = now.addingTimeInterval(61); next.publisherExpiresAt = now.addingTimeInterval(91)
        policy.receive(next, line: Data("synthetic safe frame three".utf8), at: now.addingTimeInterval(61))
        bridge.tick(reading: policy.evaluate(at: now.addingTimeInterval(61)), policy: policy, theme: ThemeStore.native, settings: s, at: now.addingTimeInterval(61))
        #expect(reloads == 2)
    }

}
