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

    /// The keycaps are buttons, within the footer.
    @Test func terminalKeycaps() {
        let ctx = RenderContext(theme: ThemeStore.terminal)
        for model in [previewPanel(.clear), previewPanel(.offline), waitingPanel(.tooOld)] {
            let s = CellsPanel.scene(model, ctx: ctx)
            #expect(Set(s.regions.keys) == ["open", "settings", "quit"])
            for r in s.regions.values { #expect(r.minY > s.marks["footer"]! && r.maxY < s.size.height) }
        }
    }
}
