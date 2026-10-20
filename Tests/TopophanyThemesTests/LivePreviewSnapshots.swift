import Foundation
import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// Panels drawn from `topo monitor stream`'s preview source, when
/// `TOPO_BIN` names a `topo` that has it.
@MainActor
@Suite(.serialized, .enabled(if: LivePreview.topo != nil)) struct LivePreviewSnapshots {
    init() { L10n.force("en") }

    func settings(_ scenario: Int, lang: String = "en") -> TopophanyKit.Settings {
        var s = TopophanyKit.Settings()
        s.topo.source = "preview"
        s.topo.scenario = scenario
        s.sections.attentionLimit = 5
        s.sections.servers = true
        s.sections.serverNodes = ["relay", "app"]
        s.sections.mac.mode = .server
        s.sections.mac.node = "mac"
        return s
    }

    @Test(arguments: [0, 1, 6, 13, 14])
    func scenario(_ n: Int) async throws {
        let s = settings(n)
        let frame = try #require(await LivePreview.frame(TemplateCompiler().request(for: s, revision: 1, lang: "en", listServers: true)))
        var policy = ReaderPolicy()
        policy.sourceStarted()
        let now = Date()
        policy.receive(frame, at: now)
        let model = SectionBuilder.panel(PanelInput(reading: policy.evaluate(at: now), engine: .running, settings: s, here: snapshotHere))
        for dark in [true, false] {
            let ctx = RenderContext(theme: ThemeStore.native, colorScheme: dark ? .dark : .light)
            try snapshot("live-native-\(dark ? "dark" : "light")-\(n)",
                         OnDesktop(dark: dark) { CardsRenderer().panel(model, context: ctx) })
        }
        try snapshot("live-terminal-\(n)", OnDesktop(dark: true) {
            CellsRenderer().panel(model, context: RenderContext(theme: ThemeStore.terminal))
        })
    }
}

/// Service cards from the preview source: pinned in the panel, and in
/// Service widgets. 1 blocks the transit line; 10 takes the origin down
/// behind the edge; 13 can't reach the collector.
@MainActor
@Suite(.serialized, .enabled(if: LivePreview.topo != nil)) struct LiveServiceSnapshots {
    init() { L10n.force("en") }

    @Test(arguments: [0, 1, 10, 13])
    func scenario(_ n: Int) async throws {
        var s = TopophanyKit.Settings()
        s.topo.source = "preview"
        s.topo.scenario = n
        s.sections.seen = false
        s.sections.attention = false
        s.sections.fleet = false
        s.sections.zones = false
        s.sections.mac.mode = .off
        s.sections.services = true
        s.sections.serviceIDs = ["vless-transit", "blog", "egress-a", "memos", "shortlink", "backup-job"]
        let request = TemplateCompiler().request(for: s, revision: 1, lang: "en", listServers: true, serviceCards: true, listServices: true)
        let frame = try #require(await LivePreview.frame(request))
        for row in frame.rows where row.metric.hasPrefix("service") {
            #expect(row.value != .malformed, "\(n) \(row.id)")
        }
        if case .services(let list)? = frame.row(TemplateCompiler.RowID.services)?.value { #expect(list.count == 23) }
        var policy = ReaderPolicy()
        policy.sourceStarted()
        let now = Date()
        policy.receive(frame, at: now)
        let model = SectionBuilder.panel(PanelInput(reading: policy.evaluate(at: now), engine: .running, settings: s, here: snapshotHere))
        #expect(model.services.count == 6 || n == 13, "\(n): \(model.services.map(\.id))")
        try snapshot("live-service-native-dark-\(n)", OnDesktop(dark: true) {
            CardsRenderer().panel(model, context: RenderContext(theme: ThemeStore.native, colorScheme: .dark))
        })
        try snapshot("live-service-terminal-\(n)", OnDesktop(dark: true) {
            CellsRenderer().panel(model, context: RenderContext(theme: ThemeStore.terminal))
        })
        for id in ["vless-transit", "blog"] {
            let w = WidgetModel(kind: .service(id: id), panel: model)
            for (size, k) in [(WidgetSize.small, "s"), (.medium, "m")] {
                try snapshot("live-service-widget-native-\(n)-\(id)-\(k)", onDesktop(w, size, theme: ThemeStore.native, dark: true))
                try snapshot("live-service-widget-terminal-\(n)-\(id)-\(k)", onDesktop(w, size, theme: ThemeStore.terminal, dark: true))
            }
        }
    }
}

enum LivePreview {
    static let topo: String? = {
        guard let p = ProcessInfo.processInfo.environment["TOPO_BIN"], !p.isEmpty,
              case .success = ProcessEngine.check(p) else { return nil }
        return p
    }()

    /// The first running frame for a request, or nil after 20 s.
    static func frame(_ request: Request) async -> Frame? {
        guard let topo else { return nil }
        let engine = ProcessEngine(configuration: .init(topoPath: topo))
        let stream = engine.start(request)
        let got = await withTaskGroup(of: Frame?.self) { group in
            group.addTask {
                for await e in stream {
                    if case .frame(let f, _) = e, f.lifecycle == .running { return f }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        await engine.stop()
        return got
    }
}
