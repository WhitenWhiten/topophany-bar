import SwiftUI
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor
@Suite(.serialized) struct MonitoringSnapshots {
    @Test func collectorStatusUsesExistingFooter() throws {
        for lang in ["en", "zh-Hans", "ja"] {
            TopophanySections.L10n.force(lang)
            defer { TopophanySections.L10n.force(nil) }
            var model = previewPanel(.offline)
            let read = try JSONDecoder().decode(CollectorRead.self, from: Data(#"{"state":"error","stage":"tls","code":"tls_timeout","duration_ms":5000,"consecutive_failures":2}"#.utf8))
            model.status.kind = .blind(.collectorUnreachable)
            model.status.collector = .init(name: "S2", read: read, isCurrent: true, now: model.status.now)
            model.sections = []
            for theme in [ThemeStore.native, ThemeStore.terminal] {
                let ctx = RenderContext(theme: theme, colorScheme: .dark)
                let size = try snapshot("collector-\(theme.id)-\(lang)", OnDesktop(dark: true) {
                    Renderers.renderer(for: theme).panel(model, context: ctx)
                })
                #expect(size.width > 0 && size.height > 0)
            }
        }
    }
}
