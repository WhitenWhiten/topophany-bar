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
        let mac = previewPanel(.incidents, settings: previewSettings(mac: .server))
        try snapshot("panel-terminal-incidents-mac", OnDesktop(dark: true) { CellsPanel(model: mac, ctx: RenderContext(theme: ThemeStore.terminal)) })
    }
}
