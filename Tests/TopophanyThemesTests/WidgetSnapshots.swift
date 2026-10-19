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
