import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor
@Suite(.serialized) struct PanelSnapshots {
    init() { L10n.force("en") }

    func panel(_ model: PanelModel, theme: Theme, dark: Bool) -> some View {
        let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
        return OnDesktop(dark: dark || theme.renderer == .cells) {
            Renderers.renderer(for: theme).panel(model, context: ctx)
        }
    }

    @Test func nativePanels() throws {
        for s in panelScenarios {
            for dark in [true, false] {
                let size = try snapshot("panel-native-\(dark ? "dark" : "light")-\(s.rawValue)",
                                        panel(previewPanel(s), theme: ThemeStore.native, dark: dark))
                #expect(abs(size.width - 392) < 0.5, "\(size)")
            }
        }
        try snapshot("panel-native-dark-incidents-server", panel(previewPanel(.incidents, settings: previewSettings(mac: .server, servers: true)), theme: ThemeStore.native, dark: true))
        try snapshot("panel-native-light-clear-server", panel(previewPanel(.clear, settings: previewSettings(mac: .server)), theme: ThemeStore.native, dark: false))
    }

    /// Taller than the screen allows: Status stays and the rest scrolls,
    /// within the height given. A snapshot doesn't draw a scroll view's
    /// rows, so their edges are checked in the running app.
    @Test func nativeScrolling() throws {
        let tall = previewPanel(.incidents, settings: previewSettings(servers: true, limit: 5))
        for dark in [true, false] {
            let ctx = RenderContext(theme: ThemeStore.native, colorScheme: dark ? .dark : .light, maxHeight: 700)
            let size = try snapshot("panel-native-\(dark ? "dark" : "light")-incidents-scrolling",
                                    OnDesktop(dark: dark) { CardsRenderer().panel(tall, context: ctx) })
            #expect(size.height <= 700 + 48 + 0.5, "\(size)")
        }
        // Unpinned, Status scrolls with the rest.
        var unpinned = tall
        unpinned.pinStatus = false
        let ctx = RenderContext(theme: ThemeStore.native, colorScheme: .dark, maxHeight: 700)
        let size = try snapshot("panel-native-dark-incidents-scrolling-unpinned",
                                OnDesktop(dark: true) { CardsRenderer().panel(unpinned, context: ctx) })
        #expect(size.height <= 700 + 48 + 0.5, "\(size)")
    }

    /// The shortest the panel may be made, in each renderer: Status, This
    /// Mac's four readings and two time zones.
    @Test func shortestPanels() throws {
        let shortest = previewPanel(.incidents).shortest
        for dark in [true, false] {
            try snapshot("panel-native-\(dark ? "dark" : "light")-shortest", panel(shortest, theme: ThemeStore.native, dark: dark))
        }
        try snapshot("panel-terminal-shortest", panel(shortest, theme: ThemeStore.terminal, dark: true))
    }

    /// A zone with more servers than its row holds: the one in trouble is
    /// among those drawn.
    @Test func crowdedZone() throws {
        var model = previewPanel(.clear)
        model.sections = model.sections.map { s in
            guard case .zones(var z) = s, let i = z.zones.firstIndex(where: \.isHere) else { return s }
            z.zones[i].servers = (1...10).map { .init(id: "n\($0)", name: "n\($0)", mark: $0 == 10 ? .down : .up) }
            return .zones(z)
        }
        try snapshot("panel-native-dark-zones-crowded", panel(model, theme: ThemeStore.native, dark: true))
        try snapshot("panel-terminal-zones-crowded", panel(model, theme: ThemeStore.terminal, dark: true))
    }

    /// Reduce Transparency paints solid fills; Increase Contrast darkens
    /// secondary text and strengthens edges and separators.
    @Test func accessibilityPanels() throws {
        for dark in [true, false] {
            let a = dark ? "dark" : "light"
            for (name, rt, hc) in [("reduce-transparency", true, false), ("increase-contrast", false, true)] {
                let ctx = RenderContext(theme: ThemeStore.native, colorScheme: dark ? .dark : .light,
                                        reduceTransparency: rt, increaseContrast: hc)
                try snapshot("panel-native-\(a)-\(name)", OnDesktop(dark: dark) {
                    CardsRenderer().panel(previewPanel(.degraded), context: ctx)
                })
            }
        }
    }

    @Test func terminalPanels() throws {
        for s in panelScenarios {
            let model = previewPanel(s)
            let ctx = RenderContext(theme: ThemeStore.terminal)
            try snapshot("panel-terminal-\(s.rawValue)", OnDesktop(dark: true) { CellsPanel(model: model, ctx: ctx, focusFirstAttention: true) })
        }
        let servers = previewPanel(.degraded, settings: previewSettings(servers: true))
        try snapshot("panel-terminal-degraded-servers", OnDesktop(dark: true) {
            CellsPanel(model: servers, ctx: RenderContext(theme: ThemeStore.terminal), focusFirstAttention: true)
        })
        // Taller than the screen allows: Status stays, the rest scrolls.
        let tall = previewPanel(.incidents, settings: previewSettings(servers: true, limit: 5))
        let short = RenderContext(theme: ThemeStore.terminal, maxHeight: 700)
        let size = try snapshot("panel-terminal-incidents-scrolling", OnDesktop(dark: true) { CellsPanel(model: tall, ctx: short) })
        #expect(size.height <= 700 + 48 + 0.5, "\(size)")
        let mac = previewPanel(.incidents, settings: previewSettings(mac: .server))
        try snapshot("panel-terminal-incidents-mac", OnDesktop(dark: true) { CellsPanel(model: mac, ctx: RenderContext(theme: ThemeStore.terminal)) })
        // Too long to sit beside the keycaps, the reason takes its own line.
        for (name, engine) in [("too-old", EngineCondition.tooOld), ("restarting", .restarting(at: snapshotOrigin.addingTimeInterval(14)))] {
            let model = waitingPanel(engine)
            try snapshot("panel-terminal-\(name)", OnDesktop(dark: true) { CellsPanel(model: model, ctx: RenderContext(theme: ThemeStore.terminal)) })
        }
    }

    /// No frame yet, for the reason the engine gives.
    func waitingPanel(_ engine: EngineCondition) -> PanelModel {
        SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: snapshotOrigin), engine: engine,
                                        settings: previewSettings(), local: sampleLocal, here: snapshotHere))
    }

    /// With nothing received there is no age, and "cached" stands alone in
    /// every language.
    @Test func terminalCachedWithoutAnAge() {
        for l in ["en", "ja", "zh-Hans"] {
            L10n.with(l) {
                let scene = CellsPanel.scene(waitingPanel(.tooOld), ctx: RenderContext(theme: ThemeStore.terminal))
                let texts = scene.items.compactMap { if case .text(_, _, let t, _, _) = $0 { t } else { nil } }
                #expect(texts.contains(" \(tr("cached")) "), "\(l): \(texts.prefix(8))")
            }
        }
    }

    /// The reason is never cut: when it doesn't fit beside the keycaps, the
    /// footer grows a line for it.
    @Test func terminalFooterReason() {
        let ctx = RenderContext(theme: ThemeStore.terminal)
        func texts(_ s: CellScene) -> [String] { s.items.compactMap { if case .text(_, _, let t, _, _) = $0 { t } else { nil } } }
        let old = CellsPanel.scene(waitingPanel(.tooOld), ctx: ctx)
        #expect(texts(old).contains("topo needs an upgrade"))
        #expect(old.size.height - old.marks["footer"]! == 48)
        let live = CellsPanel.scene(previewPanel(.clear), ctx: ctx)
        #expect(live.size.height - live.marks["footer"]! == 28)
    }

    /// The scene says where the keyboard's focus is drawn, for the scroll
    /// to bring into view; with no focus, nowhere.
    @Test func terminalFocusRegion() throws {
        let model = previewPanel(.incidents)
        let item = try #require(model.attention?.items.last)
        var ctx = RenderContext(theme: ThemeStore.terminal)
        #expect(CellsPanel.scene(model, ctx: ctx).regions["focus"] == nil)
        ctx.focus = "attention:" + item.id
        let scene = CellsPanel.scene(model, ctx: ctx)
        let r = try #require(scene.regions["focus"])
        // Where the highlight is filled, between Status and the footer.
        #expect(scene.items.contains { if case .fill(let f, _, _) = $0 { f.minY == r.minY && f.height == r.height } else { false } })
        #expect(r.minY > scene.marks["status"]! && r.maxY < scene.marks["footer"]!)
    }

    /// The keycaps are buttons, within the footer; while there's an alert,
    /// Status's `m` too.
    @Test func terminalKeycaps() throws {
        let ctx = RenderContext(theme: ThemeStore.terminal)
        for model in [previewPanel(.clear), previewPanel(.offline), waitingPanel(.tooOld)] {
            let s = CellsPanel.scene(model, ctx: ctx)
            #expect(Set(s.regions.keys) == ["open", "settings", "quit"])
            for r in s.regions.values { #expect(r.minY > s.marks["footer"]! && r.maxY < s.size.height) }
        }
        let s = CellsPanel.scene(previewPanel(.incidents), ctx: ctx)
        let quiet = try #require(s.regions["quiet"])
        #expect(Set(s.regions.keys) == ["open", "settings", "quit", "quiet"])
        #expect(quiet.minY > s.marks["header"]! && quiet.maxY < s.marks["status"]!)
    }

    /// While the panel scrolls, and only then, the footer has the quick
    /// scroll's keycap: down, or at the end back up.
    @Test func terminalLeapKeycap() throws {
        let tall = previewPanel(.incidents, settings: previewSettings(servers: true, limit: 5))
        func texts(_ s: CellScene) -> [String] { s.items.compactMap { if case .text(_, _, let t, _, _) = $0 { t } else { nil } } }
        let fits = CellsPanel.scene(tall, ctx: RenderContext(theme: ThemeStore.terminal, maxHeight: 4000))
        #expect(fits.regions["leap"] == nil)
        let short = RenderContext(theme: ThemeStore.terminal, maxHeight: 700)
        let down = CellsPanel.scene(tall, ctx: short)
        let r = try #require(down.regions["leap"])
        #expect(r.minY > down.marks["footer"]! && r.maxY < down.size.height)
        #expect(texts(down).contains(" ␣ ") && texts(down).contains(" ↓  "))
        let up = CellsPanel.scene(tall, ctx: short, leapUp: true)
        #expect(texts(up).contains(" ↑  ") && !texts(up).contains(" ↓  "))
    }

    /// A leap goes down half the panel, no further than the scroll shows,
    /// stops at the end, and from there goes back to the top.
    @Test func leapTargets() {
        #expect(PanelLeap(offset: 0, content: 2000, visible: 700).target(panel: 1000) == 500)
        #expect(PanelLeap(offset: 0, content: 2000, visible: 300).target(panel: 1000) == 300)
        #expect(PanelLeap(offset: 1100, content: 2000, visible: 700).target(panel: 1000) == 1300)
        #expect(PanelLeap(offset: 1300, content: 2000, visible: 700).atEnd)
        #expect(PanelLeap(offset: 1300, content: 2000, visible: 700).target(panel: 1000) == 0)
    }

    /// The Quiet button, and the panel once the menu bar's alert is quiet.
    @Test func quietPanels() throws {
        func quieted(_ s: FixtureEngine.Scenario) -> PanelModel {
            var m = previewPanel(s)
            m.alert = .quiet
            return m
        }
        for dark in [true, false] {
            let a = dark ? "dark" : "light"
            try snapshot("panel-native-\(a)-quiet", panel(quieted(.incidents), theme: ThemeStore.native, dark: dark))
            try snapshot("panel-native-\(a)-quiet-degraded", panel(quieted(.degraded), theme: ThemeStore.native, dark: dark))
        }
        try snapshot("panel-terminal-quiet", OnDesktop(dark: true) {
            CellsPanel(model: quieted(.incidents), ctx: RenderContext(theme: ThemeStore.terminal))
        })
    }
}
