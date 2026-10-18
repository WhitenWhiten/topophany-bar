import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// The panel and widgets in Japanese and Chinese, where text runs wider
/// and the Terminal look gives wide characters two cells.
@MainActor
@Suite(.serialized) struct LocalizedSnapshots {
    @Test(arguments: ["ja", "zh-Hans"])
    func language(_ l: String) throws {
        try L10n.with(l) {
            let model = previewPanel(.incidents, settings: previewSettings(servers: true))
            try snapshot("i18n-\(l)-panel-native", OnDesktop(dark: true) {
                CardsRenderer().panel(model, context: RenderContext(theme: ThemeStore.native, colorScheme: .dark))
            })
            try snapshot("i18n-\(l)-panel-terminal", OnDesktop(dark: true) {
                CellsRenderer().panel(model, context: RenderContext(theme: ThemeStore.terminal))
            })
            let offline = previewPanel(.offline)
            try snapshot("i18n-\(l)-panel-native-offline", OnDesktop(dark: false) {
                CardsRenderer().panel(offline, context: RenderContext(theme: ThemeStore.native, colorScheme: .light))
            })
            let w = WidgetModel(kind: .status, panel: previewPanel(.incidents, settings: previewSettings(mac: .off, servers: true)))
            try snapshot("i18n-\(l)-widget-native-m", onDesktop(w, .medium, theme: ThemeStore.native, dark: true))
            try snapshot("i18n-\(l)-widget-native-xl", onDesktop(w, .extraLarge, theme: ThemeStore.native, dark: false))
            try snapshot("i18n-\(l)-widget-terminal-l", onDesktop(w, .large, theme: ThemeStore.terminal, dark: true))
            let s = WidgetModel(kind: .server(node: "oracle-ny", isMac: false),
                                panel: previewPanel(.incidents, settings: previewSettings(mac: .off, servers: true)))
            try snapshot("i18n-\(l)-widget-native-server-m", onDesktop(s, .medium, theme: ThemeStore.native, dark: true))
            try snapshot("i18n-\(l)-widget-terminal-s", onDesktop(w, .small, theme: ThemeStore.terminal, dark: true))
        }
    }
}
