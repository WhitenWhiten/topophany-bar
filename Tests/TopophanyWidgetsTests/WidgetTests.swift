import Foundation
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
import TopophanyThemes
@testable import TopophanyWidgets

let origin = Timestamp.parse("2026-10-18T13:30:00Z")!

func settings() -> TopophanyKit.Settings {
    var s = TopophanyKit.Settings()
    s.sections.attention = false
    s.sections.mac.mode = .local
    return s
}

func policy(_ scenario: FixtureEngine.Scenario, after: TimeInterval = 4) -> ReaderPolicy {
    FixtureEngine.policy(scenario, request: TemplateCompiler().request(for: settings(), revision: 1, widgets: .init(lists: true)),
                         origin: origin, after: after)
}

func handoff(_ scenario: FixtureEngine.Scenario, after: TimeInterval = 4) -> Handoff {
    Handoff(policy: policy(scenario, after: after), theme: ThemeStore.native, settings: settings(), engineRunning: true,
            at: origin.addingTimeInterval(after))
}

func temporaryStore() -> HandoffStore {
    HandoffStore(directory: FileManager.default.temporaryDirectory.appending(path: "topophany-bar-tests-\(UUID().uuidString)"))
}

@Suite struct HandoffTests {
    init() { L10n.force("en") }

    @Test func roundTrips() throws {
        let store = temporaryStore()
        let h = handoff(.incidents)
        try store.write(h)
        let back = try #require(store.read())
        #expect(back.writtenAt == h.writtenAt)
        #expect(back.frame == h.frame)
        #expect(back.decodedTheme == ThemeStore.native)
        #expect(back.decodedSettings == settings())
    }

    @Test func showsWhatTheAppShowed() {
        let h = handoff(.incidents)
        var s = settings()
        s.sections.attention = true
        s.sections.mac.mode = .off
        let app = SectionBuilder.panel(PanelInput(reading: policy(.incidents).evaluate(at: h.writtenAt), engine: .running, settings: s))
        let widget = h.panel()
        #expect(widget.status == app.status)
        #expect(widget.status.count == 5)
        #expect(widget.attention == app.attention)
    }

    @Test func drawsListsTheBarHides() {
        let p = handoff(.incidents).panel()
        #expect(p.attention != nil)
        #expect(p.seen != nil)
        // This Mac's own readings never leave the app.
        #expect(p.mac == nil)
    }

    @Test func drawsFleetTheBarHides() {
        var s = settings()
        s.sections.fleet = false
        let p = FixtureEngine.policy(.incidents, request: TemplateCompiler().request(for: s, revision: 1, listServers: true),
                                     origin: origin, after: 4)
        let h = Handoff(policy: p, theme: ThemeStore.native, settings: s, engineRunning: true, at: origin.addingTimeInterval(4))
        #expect(h.panel().fleet?.nodeCount == 14)
    }

    @Test func listsTheServersTopoListed() {
        let p = FixtureEngine.policy(.incidents, request: TemplateCompiler().request(for: settings(), revision: 1, listServers: true),
                                     origin: origin, after: 4)
        let h = Handoff(policy: p, theme: ThemeStore.native, settings: settings(), engineRunning: true, at: origin.addingTimeInterval(4))
        #expect(h.servers().count == 14)
        #expect(h.servers().first?.id == "macbook")
        #expect(handoff(.incidents).servers().isEmpty)
    }

    @Test func emptyWithoutAnAppGroup() {
        let store = HandoffStore(appGroup: nil)
        #expect(!store.isAvailable)
        #expect(store.read() == nil)
    }
}

@Suite struct ScheduleTests {
    init() { L10n.force("en") }

    @Test func nowThenNotCurrent() {
        let h = handoff(.degraded)
        let e = WidgetSchedule.entries(h, at: h.writtenAt)
        #expect(e.count == 2)
        #expect(e[0].isCurrent && !e[1].isCurrent)
        #expect(e[1].date == h.writtenAt.addingTimeInterval(45 * 60))
        #expect(e[0].panel.status.kind == .verdict(.degraded))
        #expect(e[1].panel.status.kind == .blind(.notCurrent))
        #expect(e[1].panel.status.lastKnown?.state == "degraded")
        #expect(e[1].panel.attention == nil)
    }

    @Test func pastTheGraceOnlyNotCurrent() {
        let h = handoff(.clear)
        let e = WidgetSchedule.entries(h, at: h.writtenAt.addingTimeInterval(46 * 60))
        #expect(e.count == 1)
        #expect(!e[0].isCurrent)
        #expect(e[0].panel.status.kind == .blind(.notCurrent))
    }

    @Test func nothingHandedOff() {
        let e = WidgetSchedule.entries(nil, at: origin)
        #expect(e.count == 1)
        #expect(!e[0].isCurrent)
        #expect(e[0].panel.status.count == nil)
    }

    @Test func reloadsOnAChangeOrTheHeartbeat() {
        var r = WidgetReloadPolicy()
        let clear = handoff(.clear).panel()
        let incidents = handoff(.incidents).panel()
        let reloads = [
            r.shouldReload(clear, at: origin),
            r.shouldReload(clear, at: origin.addingTimeInterval(60)),
            r.shouldReload(incidents, at: origin.addingTimeInterval(61)),
            r.shouldReload(incidents, at: origin.addingTimeInterval(61 + 29 * 60)),
            r.shouldReload(incidents, at: origin.addingTimeInterval(61 + 30 * 60)),
        ]
        #expect(reloads == [true, false, true, false, true])
    }
}

@MainActor
@Suite struct BridgeTests {
    init() { L10n.force("en") }

    final class Count { var n = 0 }

    func panel(_ p: ReaderPolicy) -> PanelModel {
        SectionBuilder.panel(PanelInput(reading: p.evaluate(at: origin), engine: .running, settings: settings()))
    }

    @Test func writesAndReloadsOnlyOnChange() {
        let store = temporaryStore()
        let count = Count()
        let bridge = WidgetBridge(store: store) { count.n += 1 }
        let p = policy(.clear)
        bridge.tick(panel: panel(p), policy: p, theme: ThemeStore.native, settings: settings(), at: origin)
        bridge.tick(panel: panel(p), policy: p, theme: ThemeStore.native, settings: settings(), at: origin.addingTimeInterval(1))
        #expect(count.n == 1)
        #expect(store.read()?.writtenAt == origin)
        bridge.tick(panel: panel(p), policy: p, theme: ThemeStore.terminal, settings: settings(), at: origin.addingTimeInterval(2))
        #expect(count.n == 2)
        #expect(store.read()?.decodedTheme.id == "terminal")
        // A new language: the widgets draw their words again.
        var japanese = settings()
        japanese.language = .ja
        bridge.tick(panel: panel(p), policy: p, theme: ThemeStore.terminal, settings: japanese, at: origin.addingTimeInterval(3))
        #expect(count.n == 3)
        #expect(store.read()?.decodedSettings.language == .ja)
    }

    @Test func silentWithoutAnAppGroup() {
        let count = Count()
        let bridge = WidgetBridge(store: HandoffStore(appGroup: nil)) { count.n += 1 }
        let p = policy(.clear)
        bridge.tick(panel: panel(p), policy: p, theme: ThemeStore.native, settings: settings(), at: origin)
        #expect(count.n == 0)
    }
}
