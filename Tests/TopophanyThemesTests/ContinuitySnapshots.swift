import SwiftUI
import Testing
import TopophanyKit
import TopophanyEngine
import TopophanySections
@testable import TopophanyThemes

@MainActor
@Suite(.serialized) struct ContinuitySnapshots {
    @Test func historicalPanelAndWidgets() throws {
        L10n.force("zh-Hans")
        defer { L10n.force(nil) }
        let settings = previewSettings(mac: .off, servers: true, services: true)
        let request = TemplateCompiler().request(for: settings, revision: 1, widgets: .init(lists: true),
                                                 listServers: true, serviceCards: true, listServices: true)
        let reader = FixtureEngine.policy(.incidents, request: request, origin: snapshotOrigin, after: 4)
        let panel = SectionBuilder.panel(PanelInput(reading: reader.evaluate(at: snapshotOrigin.addingTimeInterval(24)),
                                                  engine: .running, settings: settings, displayHistory: true))
        #expect(panel.status.historicalAt != nil)
        #expect(!panel.chrome.isLive)
        #expect(panel.status.title == "上次数据")
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            let ctx = RenderContext(theme: theme, colorScheme: .light)
            try snapshot("continuity-panel-\(theme.id)", OnDesktop(dark: false) {
                Renderers.renderer(for: theme).panel(panel, context: ctx)
            })
            for (name, kind, size) in [("status", WidgetModel.Kind.status, WidgetSize.small),
                                       ("server", .server(node: "oracle-ny", isMac: false), .small),
                                       ("map", .map(frame: nil), .medium)] {
                try snapshot("continuity-\(theme.id)-\(name)", onDesktop(WidgetModel(kind: kind, panel: panel), size,
                                                                       theme: theme, dark: false))
            }
        }
    }
}
