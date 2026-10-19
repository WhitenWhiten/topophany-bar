import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// The built-in themes beyond Native and Terminal on every surface: the
/// panel, each widget size and the menu bar item, in each appearance they
/// draw in; and all of them side by side.
@MainActor
@Suite(.serialized) struct ThemeSnapshots {
    init() { L10n.force("en") }

    static let themes = ThemeStore.builtIn.filter { $0.id != "native" && $0.id != "terminal" }

    /// The appearances a theme draws in, by name.
    func appearances(_ theme: Theme) -> [(dark: Bool, name: String)] {
        switch theme.appearance {
        case .system: [(true, "-dark"), (false, "-light")]
        case .dark: [(true, "")]
        case .light: [(false, "")]
        }
    }

    func panel(_ model: PanelModel, theme: Theme, dark: Bool) -> some View {
        let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
        return OnDesktop(dark: dark) { Renderers.renderer(for: theme).panel(model, context: ctx) }
    }

    @Test func panels() throws {
        for theme in Self.themes {
            for (dark, a) in appearances(theme) {
                for s in panelScenarios {
                    try snapshot("theme-\(theme.id)\(a)-panel-\(s.rawValue)", panel(previewPanel(s), theme: theme, dark: dark))
                }
                try snapshot("theme-\(theme.id)\(a)-panel-servers",
                             panel(previewPanel(.degraded, settings: previewSettings(mac: .server, servers: true)), theme: theme, dark: dark))
            }
        }
    }

    @Test func widgets() throws {
        let status = WidgetModel(kind: .status, panel: previewPanel(.incidents, settings: previewSettings(mac: .off, servers: true)))
        let clear = WidgetModel(kind: .status, panel: previewPanel(.clear, settings: previewSettings(mac: .off, servers: true)))
        let server = WidgetModel(kind: .server(node: "oracle-ny", isMac: false),
                                 panel: previewPanel(.incidents, settings: previewSettings(mac: .server, servers: true)))
        for theme in Self.themes {
            for (dark, a) in appearances(theme) {
                for (size, n) in WidgetSnapshots.sizes {
                    try snapshot("theme-\(theme.id)\(a)-widget-status-\(n)", onDesktop(status, size, theme: theme, dark: dark))
                }
                try snapshot("theme-\(theme.id)\(a)-widget-status-m-clear", onDesktop(clear, .medium, theme: theme, dark: dark))
                try snapshot("theme-\(theme.id)\(a)-widget-server-m", onDesktop(server, .medium, theme: theme, dark: dark))
            }
        }
    }

    @Test func items() throws {
        for theme in Self.themes {
            for dark in [true, false] {
                let rows = VStack(alignment: .leading, spacing: 0) {
                    ForEach(panelScenarios, id: \.self) { s in
                        HStack(spacing: 14) {
                            ForEach(TopophanyKit.Settings.Appearance.Show.allCases, id: \.self) { show in
                                var a = TopophanyKit.Settings.Appearance.MenuBar()
                                let _ = a.show = show
                                let model = StatusItemModel(status: previewPanel(s).status, appearance: a)
                                Renderers.renderer(for: theme).statusItem(model, context: StatusItemContext(theme: theme, menuBarIsDark: dark))
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(dark ? Color(white: 0.11, opacity: 0.85) : Color(white: 0.97, opacity: 0.85))
                    }
                }
                try snapshot("theme-\(theme.id)-item-\(dark ? "dark" : "light")", OnDesktop(dark: dark, padding: 12) { rows })
            }
        }
    }

    /// Every built-in theme as Settings offers it: a chip of its colors,
    /// with the panel light and dark.
    @Test func swatches() throws {
        let rows = VStack(alignment: .leading, spacing: 10) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                HStack(spacing: 8) {
                    ForEach(ThemeStore.builtIn, id: \.id) { t in
                        ThemeSwatch(theme: t, colorScheme: scheme).frame(width: 68, height: 40)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(scheme == .dark ? Color(white: 0.17) : Color(white: 0.96)))
            }
        }
        let size = try snapshot("themes-swatches", OnDesktop(dark: true, padding: 12) { rows })
        #expect(abs(size.width - (6 * 68 + 5 * 8 + 20 + 24)) < 0.5, "\(size)")
    }

    /// Every built-in theme's panel in one row, in each appearance.
    @Test func gallery() throws {
        for dark in [true, false] {
            let themes = ThemeStore.builtIn.filter { $0.appearance == .system || ($0.appearance == .dark) == dark }
            let model = previewPanel(.incidents, settings: previewSettings(mac: .local))
            let row = HStack(alignment: .top, spacing: 24) {
                ForEach(themes, id: \.id) { t in
                    Renderers.renderer(for: t).panel(model, context: RenderContext(theme: t, colorScheme: dark ? .dark : .light))
                }
            }
            try snapshot("themes-gallery-\(dark ? "dark" : "light")", scale: 1, OnDesktop(dark: dark) { row })
        }
    }
}
