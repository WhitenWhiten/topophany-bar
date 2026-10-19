import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// A widget on the desktop, as WidgetKit would place it: the renderer's
/// background under its content, in a 22 pt rounded square. `bounds` is
/// the design's size unless given.
@MainActor
func onDesktop(_ model: WidgetModel, _ size: WidgetSize, bounds: CGSize? = nil, theme: Theme, dark: Bool,
               rendering: RenderContext.WidgetRendering = .fullColor) -> some View {
    let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light, widgetRendering: rendering)
    let r = Renderers.renderer(for: theme)
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    return OnDesktop(dark: dark || theme.renderer == .cells) {
        r.widget(model, size: size, bounds: bounds ?? CGSize(width: size.width, height: size.height), context: ctx)
            .background(r.widgetBackground(context: ctx))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.18 : 0.7), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 12)
    }
}

@MainActor
@Suite(.serialized) struct WidgetSnapshots {
    init() { L10n.force("en") }

    static let sizes: [(WidgetSize, String)] = [(.small, "s"), (.medium, "m"), (.large, "l"), (.extraLarge, "xl")]

    /// WidgetKit's sizes on a 1920×1080 pt display: a 164 pt grid with
    /// 16 pt gaps, smaller than the design's.
    static let smaller: [WidgetSize: CGSize] = [
        .small: CGSize(width: 164, height: 164), .medium: CGSize(width: 344, height: 164),
        .large: CGSize(width: 344, height: 344), .extraLarge: CGSize(width: 704, height: 344),
    ]

    func status(_ s: FixtureEngine.Scenario, servers: Bool = true) -> WidgetModel {
        WidgetModel(kind: .status, panel: previewPanel(s, settings: previewSettings(mac: .off, servers: servers)))
    }

    func server(_ node: String, isMac: Bool) -> WidgetModel {
        WidgetModel(kind: .server(node: node, isMac: isMac),
                    panel: previewPanel(.incidents, settings: previewSettings(mac: .server, servers: true)))
    }

    @Test func nativeSizes() throws {
        for dark in [true, false] {
            let a = dark ? "dark" : "light"
            for (size, n) in Self.sizes {
                let s = try snapshot("widget-native-\(a)-status-\(n)", onDesktop(status(.incidents), size, theme: ThemeStore.native, dark: dark))
                #expect(abs(s.width - (size.width + 48)) < 0.5 && abs(s.height - (size.height + 48)) < 0.5, "\(n): \(s)")
            }
            try snapshot("widget-native-\(a)-server-s", onDesktop(server("oracle-ny", isMac: false), .small, theme: ThemeStore.native, dark: dark))
            try snapshot("widget-native-\(a)-server-m", onDesktop(server("oracle-ny", isMac: false), .medium, theme: ThemeStore.native, dark: dark))
            try snapshot("widget-native-\(a)-server-m-mac", onDesktop(server("macbook", isMac: true), .medium, theme: ThemeStore.native, dark: dark))
        }
        try snapshot("widget-native-dark-status-m-clear", onDesktop(status(.clear), .medium, theme: ThemeStore.native, dark: false))
        try snapshot("widget-native-dark-status-xl-clear", onDesktop(status(.clear), .extraLarge, theme: ThemeStore.native, dark: true))
    }

    @Test func terminalSizes() throws {
        for (size, n) in Self.sizes {
            try snapshot("widget-terminal-status-\(n)", onDesktop(status(.incidents), size, theme: ThemeStore.terminal, dark: true))
        }
        try snapshot("widget-terminal-server-s", onDesktop(server("oracle-ny", isMac: false), .small, theme: ThemeStore.terminal, dark: true))
        try snapshot("widget-terminal-server-m", onDesktop(server("oracle-ny", isMac: false), .medium, theme: ThemeStore.terminal, dark: true))
        try snapshot("widget-terminal-status-m-clear", onDesktop(status(.clear), .medium, theme: ThemeStore.terminal, dark: true))
        for s in panelScenarios {
            try snapshot("widget-terminal-state-\(s.rawValue)", onDesktop(status(s), .small, theme: ThemeStore.terminal, dark: true))
        }
        let stale = status(.incidents).notCurrent(at: snapshotOrigin.addingTimeInterval(47 * 60))
        try snapshot("widget-terminal-state-not-current", onDesktop(stale, .small, theme: ThemeStore.terminal, dark: true))
    }

    @Test func smallerSizes() throws {
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for dark in theme.renderer == .cells ? [true] : [true, false] {
                let a = theme.renderer == .cells ? "" : dark ? "-dark" : "-light"
                for (size, n) in Self.sizes {
                    let b = try #require(Self.smaller[size])
                    let s = try snapshot("widget-\(theme.id)\(a)-status-\(n)-1080",
                                         onDesktop(status(.incidents), size, bounds: b, theme: theme, dark: dark))
                    #expect(abs(s.width - (b.width + 48)) < 0.5 && abs(s.height - (b.height + 48)) < 0.5, "\(n): \(s)")
                }
                for (size, n) in [(WidgetSize.small, "s"), (.medium, "m")] {
                    try snapshot("widget-\(theme.id)\(a)-server-\(n)-1080",
                                 onDesktop(server("oracle-ny", isMac: false), size, bounds: Self.smaller[size], theme: theme, dark: dark))
                }
            }
        }
    }

    /// More applications than any size holds, as a larger topology
    /// declares, with trouble near the end.
    func crowded() throws -> WidgetModel {
        var panel = previewPanel(.clear, settings: previewSettings(mac: .off, servers: true))
        let i = try #require(panel.sections.firstIndex { if case .applications = $0 { true } else { false } })
        guard case .applications(let a) = panel.sections[i] else { return status(.clear) }
        var rows = (0..<13).map { k in
            var r = a.rows[k % a.rows.count]
            r.id += "-\(k)"
            r.name = "\(r.name) \(k + 1)"
            return r
        }
        rows[11].mark = .degraded
        rows[11].services[0] = .degraded
        panel.sections[i] = .applications(ApplicationsSection(rows: rows, isCurrent: true))
        return WidgetModel(kind: .status, panel: panel)
    }

    /// Every box ends above the widget's bottom, whatever the lists hold:
    /// what doesn't fit is counted on a last line.
    @Test func terminalListsFit() throws {
        let model = try crowded()
        for theme in [ThemeStore.terminal, ThemeStore.paper] {
            for (size, n) in Self.sizes {
                for (bounds, tag) in [(CGSize(width: size.width, height: size.height), ""), (try #require(Self.smaller[size]), "-1080")] {
                    let scene = CellsWidget.scene(model, size: size, bounds: bounds, ctx: RenderContext(theme: theme))
                    let bottom = scene.items.map { item -> Double in
                        switch item {
                        case .text(_, let y, _, _, _), .glyph(_, let y, _, _): y + scene.metrics.line
                        case .fill(let r, _, _), .shaded(let r, _, _, _), .box(let r, _, _, _), .stripes(let r, _, _): r.maxY
                        case .line(let a, let b, _, _, _): max(a.y, b.y)
                        }
                    }.max() ?? 0
                    #expect(bottom <= bounds.height - 6, "\(theme.id) \(n)\(tag): \(bottom) of \(bounds.height)")
                    let texts = scene.items.compactMap { if case .text(_, _, let t, _, _) = $0 { t } else { nil } }
                    if size != .small { #expect(texts.contains { $0.contains("more") }, "\(theme.id) \(n)\(tag) counts the rest") }
                }
                try snapshot("widget-\(theme.id)-crowded-\(n)-1080",
                             onDesktop(model, size, bounds: Self.smaller[size], theme: theme, dark: true))
            }
        }
        for (size, n) in Self.sizes where size != .small {
            try snapshot("widget-native-dark-crowded-\(n)-1080", onDesktop(model, size, bounds: Self.smaller[size], theme: ThemeStore.native, dark: true))
        }
    }

    @Test func monochrome() throws {
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for (size, n) in [(WidgetSize.small, "s"), (.medium, "m")] {
                try snapshot("widget-\(theme.id)-vibrant-\(n)",
                             onDesktop(status(.incidents), size, theme: theme, dark: true, rendering: .vibrant).grayscale(1))
            }
        }
    }

    @Test func nativeStates() throws {
        for dark in [true, false] {
            for s in panelScenarios {
                try snapshot("widget-native-\(dark ? "dark" : "light")-state-\(s.rawValue)",
                             onDesktop(status(s), .small, theme: ThemeStore.native, dark: dark))
            }
            let stale = status(.incidents).notCurrent(at: snapshotOrigin.addingTimeInterval(47 * 60))
            try snapshot("widget-native-\(dark ? "dark" : "light")-state-not-current",
                         onDesktop(stale, .small, theme: ThemeStore.native, dark: dark))
            try snapshot("widget-native-\(dark ? "dark" : "light")-l-not-current",
                         onDesktop(stale, .large, theme: ThemeStore.native, dark: dark))
            let staleServer = server("oracle-ny", isMac: false).notCurrent(at: snapshotOrigin.addingTimeInterval(47 * 60))
            try snapshot("widget-native-\(dark ? "dark" : "light")-server-m-not-current",
                         onDesktop(staleServer, .medium, theme: ThemeStore.native, dark: dark))
        }
        try snapshot("widget-native-dark-server-s-missing",
                     onDesktop(server("no-such-node", isMac: false), .small, theme: ThemeStore.native, dark: true))
    }
}
