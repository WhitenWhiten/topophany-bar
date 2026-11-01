import SwiftUI
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor
@Suite(.serialized) struct MonitoringSnapshots {
    @Test func monitoringCardsUseBothExistingRenderers() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/preview.ndjson")
        let f = try #require(FrameDecoder.frame(from: Data(contentsOf: url)))
        let now = try #require(f.generatedAt)
        var policy = ReaderPolicy(); policy.receive(f, at: now)
        let pins: [MonitorPin] = [.init(kind: .check, id: "m-clash"), .init(kind: .link, id: "home-cf")]
        for lang in ["en", "zh-Hans", "ja"] {
            L10n.force(lang)
            defer { L10n.force(nil) }
            for expanded in [false, true] {
                var model = previewPanel(.clear)
                model.sections = [.services(SectionBuilder.monitors(policy.evaluate(at: now), pins: pins, expanded: expanded ? Set(pins) : []))]
                for theme in [ThemeStore.native, ThemeStore.terminal] {
                    let ctx = RenderContext(theme: theme, colorScheme: .dark)
                    try snapshot("monitors-\(theme.id)-\(lang)-\(expanded ? "expanded" : "compact")", OnDesktop(dark: true) {
                        Renderers.renderer(for: theme).panel(model, context: ctx)
                    })
                }
            }
        }
    }

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
