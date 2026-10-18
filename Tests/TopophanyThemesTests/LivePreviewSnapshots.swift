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
        let frame = try #require(await LivePreview.frame(TemplateCompiler().request(for: s, revision: 1, lang: "en")))
        var policy = ReaderPolicy()
        policy.sourceStarted()
        let now = Date()
        policy.receive(frame, at: now)
        let model = SectionBuilder.panel(PanelInput(reading: policy.evaluate(at: now), engine: .running, settings: s))
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
