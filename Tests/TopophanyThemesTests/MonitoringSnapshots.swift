import SwiftUI
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor
@Suite(.serialized) struct MonitoringSnapshots {
    @Test func monitoringAdaptsToLargeTextAndEveryTheme() throws {
        L10n.force("zh-Hans")
        defer { L10n.force(nil) }
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/preview.ndjson")
        let f = try #require(FrameDecoder.frame(from: Data(contentsOf: url)))
        let now = try #require(f.generatedAt)
        var policy = ReaderPolicy(); policy.receive(f, at: now)
        let pin = MonitorPin(kind: .check, id: "m-clash")
        var model = previewPanel(.clear)
        model.sections = [.services(SectionBuilder.monitors(policy.evaluate(at: now), pins: [pin], expanded: [pin]))]
        for theme in ThemeStore.builtIn {
            let ctx = RenderContext(theme: theme, colorScheme: .light, textSize: .large)
            try snapshot("monitor-large-\(theme.id)", OnDesktop(dark: false) {
                Renderers.renderer(for: theme).panel(model, context: ctx).transaction { $0.disablesAnimations = true }
            })
        }
    }

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

    @Test func checkWidgetsInBothRenderers() throws {
        L10n.force("en")
        defer { L10n.force(nil) }
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/preview.ndjson")
        let f = try #require(FrameDecoder.frame(from: Data(contentsOf: url)))
        let now = try #require(f.generatedAt)
        var policy = ReaderPolicy(); policy.receive(f, at: now)
        let reading = policy.evaluate(at: now)
        for pin in [MonitorPin(kind: .check, id: "m-clash"), MonitorPin(kind: .link, id: "home-cf"), MonitorPin(kind: .check, id: "")] {
            var panel = previewPanel(.clear)
            panel.sections = [.services(SectionBuilder.monitors(reading, pins: [pin], expanded: [pin]))]
            let model = WidgetModel(kind: .monitor(pin: pin), panel: panel)
            if !pin.entity.isEmpty { #expect(model.monitor != nil) }
            for theme in [ThemeStore.native, ThemeStore.terminal] {
                for (size, n) in [(WidgetSize.small, "s"), (.medium, "m")] {
                    let name = pin.entity.isEmpty ? "none" : pin.entity
                    let drawn = try snapshot("check-widget-\(theme.id)-\(name)-\(n)", onDesktop(model, size, theme: theme, dark: true))
                    #expect(drawn.width > 0)
                }
            }
        }
    }

    /// Preview scenario 10's services: an access failure that is not an
    /// outage by itself, and services whose availability is unknown.
    @Test func serviceAssessmentsInBothRenderers() throws {
        L10n.force("en")
        defer { L10n.force(nil) }
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/assessment.ndjson")
        let line = try Data(contentsOf: url)
        let f = try #require(FrameDecoder.frame(from: line))
        let now = try #require(f.generatedAt)
        var policy = ReaderPolicy(); policy.receive(f, line: line, at: now)
        let reading = policy.evaluate(at: now)
        var model = previewPanel(.clear)
        // The fixture's own verdict, with the reasons coverage gives.
        model.status = SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: TopophanyKit.Settings())).status
        model.sections = [.services(SectionBuilder.services(reading, ids: ["memos", "blog", "home-rproxy"]))]
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            let ctx = RenderContext(theme: theme, colorScheme: .dark)
            try snapshot("service-assessment-\(theme.id)", OnDesktop(dark: true) { Renderers.renderer(for: theme).panel(model, context: ctx) })
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
