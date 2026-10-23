import Foundation
import SwiftUI
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor @Suite(.serialized) struct DirectSnapshots {
    func model(_ state: String, at: Date? = nil, pinned: Bool = true) throws -> PanelModel {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/DirectDevelopment")
        let now = Timestamp.parse("2026-10-21T12:00:00Z")!
        let data = try Data(contentsOf: root.appending(path: state + ".json"))
        let frame = try #require(FrameDecoder.frame(from: data))
        var p = ReaderPolicy(); p.receive(frame, line: data, at: now)
        var s = Settings(); s.topo.source = "direct"; s.sections.servers = true; s.sections.mac.mode = .off
        s.sections.serverNodes = pinned ? frame.rows.compactMap(\.select?.node) : []
        return SectionBuilder.panel(.init(reading: p.evaluate(at: at ?? now), engine: .running, settings: s))
    }
    @Test func sourcePanels() throws {
        for language in ["en", "ja", "zh-Hans"] {
            try L10n.with(language) {
                for state in ["loading", "ready", "partial", "no_data", "auth_required", "forbidden", "retrying", "unknown", "expired",
                              "fleet", "fleet_partial", "fleet_expired"] {
                    let expired = state.hasSuffix("expired")
                    let m = try model(expired ? (state == "expired" ? "ready" : "fleet") : state,
                                      at: expired ? Timestamp.parse("2026-10-21T12:03:01Z") : nil)
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
                for fixture in ["ready", "fleet", "fleet_partial"] {
                    for expired in [false, true] {
                        // A widget's later entry, past the snapshot's deadlines.
                        let panel = try model(fixture)
                        for theme in ThemeStore.builtIn {
                            for size in WidgetSize.allCases {
                                for server in [false, true] {
                                    let kind: WidgetModel.Kind = server ? .server(node: panel.servers[0].id, isMac: false) : .status
                                    var widget = WidgetModel(kind: kind, panel: panel)
                                    if expired { widget = widget.notCurrent(at: Timestamp.parse("2026-10-21T12:03:01Z")!) }
                                    let name = "direct-widget-\(language)-\(fixture)-\(theme.id)-\(size.rawValue)-\(server ? "server" : "status")-\(expired ? "expired" : "current")"
                                    try snapshot(name, onDesktop(widget, size, theme: theme, dark: theme.appearance != .light))
                                    // The sizes WidgetKit gives on a 1920×1080 pt display, where crowding shows first.
                                    if fixture == "fleet_partial", let bounds = WidgetSnapshots.smaller[size] {
                                        try snapshot(name + "-1080", onDesktop(widget, size, bounds: bounds, theme: theme, dark: theme.appearance != .light))
                                        // In one tone, as the desktop draws widgets behind another app.
                                        try snapshot(name + "-vibrant", onDesktop(widget, size, theme: theme, dark: theme.appearance != .light,
                                                                                  rendering: .vibrant))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// A small Server widget for servers whose readings aren't current,
    /// where the pill is widest: STALE and NO SAMPLES.
    @Test func serversWithoutCurrentReadings() throws {
        let panel = try model("fleet_partial")
        for theme in ThemeStore.builtIn {
            for card in panel.servers where card.samples != .current {
                let widget = WidgetModel(kind: .server(node: card.id, isMac: false), panel: panel)
                let name = "direct-widget-en-\(card.name)-\(theme.id)-small-server"
                try snapshot(name, onDesktop(widget, .small, theme: theme, dark: theme.appearance != .light))
                if let bounds = WidgetSnapshots.smaller[.small] {
                    try snapshot(name + "-1080", onDesktop(widget, .small, bounds: bounds, theme: theme, dark: theme.appearance != .light))
                }
            }
        }
    }

    /// More servers than tiles hold: the large and extra large Status
    /// widgets list them a row each.
    @Test func manyServers() throws {
        var panel = try model("fleet")
        let cards = panel.servers
        for count in [7, 12] {
            let many = (0..<count).map { i in
                var c = cards[i % cards.count]
                c.id += "-\(i)"
                c.name += "-\(i)"
                return c
            }
            panel.sections = panel.sections.map { if case .servers = $0 { .servers(many) } else { $0 } }
            for theme in [ThemeStore.native, ThemeStore.terminal] {
                for size in [WidgetSize.large, .extraLarge] {
                    try snapshot("direct-widget-en-\(count)-servers-\(theme.id)-\(size.rawValue)",
                                 onDesktop(WidgetModel(kind: .status, panel: panel), size, theme: theme, dark: true))
                }
            }
        }
    }

    /// With no server pinned, a medium Status widget lists its sources.
    @Test func sourcesWithoutServers() throws {
        let panel = try model("fleet_partial", pinned: false)
        for theme in ThemeStore.builtIn {
            try snapshot("direct-widget-en-unpinned-\(theme.id)-medium-status",
                         onDesktop(WidgetModel(kind: .status, panel: panel), .medium, theme: theme, dark: theme.appearance != .light))
        }
    }

    /// A collector whose servers are read from Komari and a Beszel Hub:
    /// judged ones keep their pills, a stale one says so.
    @Test func collectorSourcePanels() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/CollectorSources")
        let now = Timestamp.parse("2026-10-21T12:00:00Z")!
        let data = try Data(contentsOf: root.appending(path: "komari.json"))
        let frame = try #require(FrameDecoder.frame(from: data))
        var policy = ReaderPolicy(); policy.receive(frame, line: data, at: now)
        var s = Settings(); s.sections.servers = true; s.sections.fleet = true; s.sections.mac.mode = .off
        s.sections.seen = false; s.sections.map = false; s.sections.zones = false
        s.sections.serverNodes = frame.rows.compactMap(\.select?.node)
        let panel = SectionBuilder.panel(.init(reading: policy.evaluate(at: now), engine: .running, settings: s))
        for language in ["en", "ja", "zh-Hans"] {
            try L10n.with(language) {
                let m = SectionBuilder.panel(.init(reading: policy.evaluate(at: now), engine: .running, settings: s))
                for theme in ThemeStore.builtIn {
                    for dark in theme.id == "native" ? [true, false] : [theme.appearance != .light] {
                        let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
                        try snapshot("komari-\(language)-\(theme.id)-\(dark ? "dark" : "light")", OnDesktop(dark: dark) {
                            Renderers.renderer(for: theme).panel(m, context: ctx).transaction { $0.disablesAnimations = true }
                        })
                    }
                }
            }
        }
        for theme in ThemeStore.builtIn {
            for (size, node) in [(WidgetSize.small, "hk-1"), (.small, "fra-3"), (.medium, "tokyo-2")] {
                let widget = WidgetModel(kind: .server(node: node, isMac: false), panel: panel)
                try snapshot("komari-widget-\(theme.id)-\(size.rawValue)-\(node)", onDesktop(widget, size, theme: theme, dark: theme.appearance != .light))
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
