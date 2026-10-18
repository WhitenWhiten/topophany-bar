import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// The menu bar item in every state and Show mode, on a menu bar strip.
@MainActor
@Suite(.serialized) struct StatusItemSnapshots {
    init() { L10n.force("en") }

    func strip(theme: Theme, dark: Bool, colors: Bool = true, _ scenario: FixtureEngine.Scenario) -> some View {
        let status = previewPanel(scenario).status
        let r = Renderers.renderer(for: theme)
        return HStack(spacing: 14) {
            ForEach(TopophanyKit.Settings.Appearance.Show.allCases, id: \.self) { show in
                var a = TopophanyKit.Settings.Appearance.MenuBar()
                let _ = (a.show = show, a.statusColors = colors)
                let template = theme.renderer == .cards && !colors
                r.statusItem(StatusItemModel(status: status, appearance: a),
                             context: StatusItemContext(theme: theme, menuBarIsDark: dark, template: template))
                    .foregroundStyle(dark ? .white : .black)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(dark ? Color(white: 0.11, opacity: 0.85) : Color(white: 0.97, opacity: 0.85))
    }

    @Test func items() throws {
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for dark in [true, false] {
                let rows = VStack(alignment: .leading, spacing: 0) {
                    ForEach(panelScenarios, id: \.self) { s in strip(theme: theme, dark: dark, s) }
                    if theme.renderer == .cards {
                        ForEach(panelScenarios, id: \.self) { s in strip(theme: theme, dark: dark, colors: false, s) }
                    }
                }
                try snapshot("item-\(theme.id)-\(dark ? "dark" : "light")", OnDesktop(dark: dark, padding: 12) { rows })
            }
        }
    }
}
