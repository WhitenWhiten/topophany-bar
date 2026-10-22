import Foundation
import SwiftUI
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor @Suite(.serialized) struct DirectSnapshots {
    func model(_ state: String, at: Date? = nil) throws -> PanelModel {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/DirectDevelopment")
        let now = Timestamp.parse("2026-10-21T12:00:00Z")!
        let data = try Data(contentsOf: root.appending(path: state + ".json"))
        let frame = try #require(FrameDecoder.frame(from: data))
        var p = ReaderPolicy(); p.receive(frame, line: data, at: now)
        var s = Settings(); s.topo.source = "direct"; s.sections.servers = true; s.sections.mac.mode = .off
        s.sections.serverNodes = [frame.rows.last!.select!.node!]
        return SectionBuilder.panel(.init(reading: p.evaluate(at: at ?? now), engine: .running, settings: s))
    }
    @Test func sourcePanels() throws {
        for language in ["en", "ja", "zh-Hans"] {
            try L10n.with(language) {
                for state in ["loading", "ready", "partial", "no_data", "auth_required", "forbidden", "retrying", "unknown", "expired"] {
                    let m = try model(state == "expired" ? "ready" : state, at: state == "expired" ? Timestamp.parse("2026-10-21T12:03:01Z") : nil)
                    for theme in ThemeStore.builtIn {
                        for dark in theme.id == "native" ? [true, false] : [theme.appearance != .light] {
                            let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
                            try snapshot("direct-\(language)-\(theme.id)-\(dark ? "dark" : "light")-\(state)", OnDesktop(dark: dark) {
                                Renderers.renderer(for: theme).panel(m, context: ctx).transaction { $0.disablesAnimations = true }
                            })
                        }
                    }
                }
            }
        }
    }
    @Test func resourceWidgets() throws {
        for language in ["en", "ja", "zh-Hans"] {
            try L10n.with(language) {
                for expired in [false, true] {
                    let panel = try model("ready", at: expired ? Timestamp.parse("2026-10-21T12:03:01Z") : nil)
                    for theme in ThemeStore.builtIn {
                        for size in WidgetSize.allCases {
                            for server in [false, true] {
                                let kind: WidgetModel.Kind = server ? .server(node: panel.servers[0].id, isMac: false) : .status
                                let widget = WidgetModel(kind: kind, panel: panel, isCurrent: !expired)
                                try snapshot("direct-widget-\(language)-\(theme.id)-\(size.rawValue)-\(server ? "server" : "status")-\(expired ? "expired" : "current")",
                                    onDesktop(widget, size, theme: theme, dark: theme.appearance != .light))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func officialContractPanels() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/contracts/direct-v1/fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("stream-") }
        for file in files {
            let bytes = try Data(contentsOf: file)
            let frame = try #require(FrameDecoder.frame(from: bytes))
            guard frame.lifecycle == .running else { continue }
            let now = try #require(frame.generatedAt)
            var policy = ReaderPolicy(); policy.receive(frame, line: bytes, at: now)
            var s = Settings(); s.topo.source = "direct"; s.sections.servers = true; s.sections.mac.mode = .off
            s.sections.serverNodes = frame.rows.compactMap(\.select?.node)
            let model = SectionBuilder.panel(.init(reading: policy.evaluate(at: now), engine: .running, settings: s))
            #expect(model.status.sources != nil)
            for theme in ThemeStore.builtIn {
                let ctx = RenderContext(theme: theme)
                try snapshot("contract-\(file.deletingPathExtension().lastPathComponent)-\(theme.id)", OnDesktop(dark: theme.appearance != .light) {
                    Renderers.renderer(for: theme).panel(model, context: ctx)
                })
            }
        }
    }

}
