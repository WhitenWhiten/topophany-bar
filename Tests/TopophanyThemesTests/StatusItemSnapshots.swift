import SwiftUI
import LocalReadings
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// The menu bar item in every state and Show mode, on a menu bar strip, and
/// its motion frame by frame.
@MainActor
@Suite(.serialized) struct StatusItemSnapshots {
    init() { L10n.force("en") }

    func item(_ scenario: FixtureEngine.Scenario, show: TopophanyKit.Settings.Appearance.Show = .count, colors: Bool = true,
              readings: [TopophanyKit.Settings.Appearance.MenuBar.Reading] = [], local: LocalSnapshot? = sampleLocal,
              quiet: Bool = false) -> StatusItemModel {
        var a = TopophanyKit.Settings.Appearance.MenuBar()
        a.show = show
        a.statusColors = colors
        a.readings = readings
        let status = previewPanel(scenario).status
        return StatusItemModel(status: status, appearance: a, local: local, quiet: quiet ? QuietAlert(status) : nil)
    }

    func drawn(_ model: StatusItemModel, theme: Theme, dark: Bool, motion: StatusItemMotion = .still) -> some View {
        Renderers.renderer(for: theme).statusItem(model, context: StatusItemContext(theme: theme, menuBarIsDark: dark, motion: motion))
    }

    func bar<Content: View>(dark: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 14) { content() }
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(dark ? Color(white: 0.11, opacity: 0.85) : Color(white: 0.97, opacity: 0.85))
    }

    func strip(theme: Theme, dark: Bool, colors: Bool = true, _ scenario: FixtureEngine.Scenario) -> some View {
        bar(dark: dark) {
            ForEach(TopophanyKit.Settings.Appearance.Show.allCases, id: \.self) { show in
                drawn(item(scenario, show: show, colors: colors), theme: theme, dark: dark)
            }
        }
    }

    @Test func items() throws {
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for dark in [true, false] {
                let rows = VStack(alignment: .leading, spacing: 0) {
                    ForEach(panelScenarios, id: \.self) { s in strip(theme: theme, dark: dark, s) }
                    if theme.renderer == .cards {
                        ForEach(panelScenarios, id: \.self) { s in strip(theme: theme, dark: dark, colors: false, s) }
                    }
                }
                try snapshot("item-\(theme.id)-\(dark ? "dark" : "light")", OnDesktop(dark: dark, padding: 12) { rows })
            }
        }
    }

    /// White Night's moon says each status itself, with no badge: a row
    /// per status in color and quieted, then each size of the panorama.
    @Test func whiteNightPanorama() throws {
        func night(_ scenario: FixtureEngine.Scenario, show: TopophanyKit.Settings.Appearance.Show = .count, quiet: Bool = false,
                   size: Int = 26) -> StatusItemModel {
            var m = item(scenario, show: show, quiet: quiet)
            m.icon = .whiteNight
            m.iconSize = size
            return m
        }
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            let rows = VStack(alignment: .leading, spacing: 12) {
                ForEach([false, true], id: \.self) { dark in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(panelScenarios, id: \.self) { s in
                            HStack(spacing: 20) {
                                ForEach(TopophanyKit.Settings.Appearance.Show.allCases, id: \.self) { show in
                                    drawn(night(s, show: show), theme: theme, dark: dark)
                                }
                                if s == .degraded || s == .incidents {
                                    drawn(night(s, quiet: true), theme: theme, dark: dark)
                                }
                            }
                        }
                        HStack(spacing: 20) {
                            ForEach([18, 22, 26], id: \.self) { size in
                                drawn(night(.incidents, show: .symbol, size: size), theme: theme, dark: dark,
                                      motion: StatusItemMotion(moves: true, time: 6))
                            }
                        }
                    }
                    .padding(10)
                    .background(dark ? Color(white: 0.11) : Color(white: 0.95))
                }
            }
            try snapshot("item-white-night-\(theme.id)", rows)
        }
    }

    /// A pack's own frames for the statuses it has, and the badge beside
    /// its clear frames for those it hasn't.
    @Test func statusPack() throws {
        func tile(_ rgb: UInt32, _ shape: Int) -> CGImage? {
            let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 48 * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.setFillColor(CGColor(red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255,
                                          blue: Double(rgb & 255) / 255, alpha: 1))
            let r = CGRect(x: 6, y: 6, width: 36, height: 36)
            switch shape {
            case 0: context?.fillEllipse(in: r)
            case 1:
                context?.move(to: CGPoint(x: 24, y: 42)); context?.addLine(to: CGPoint(x: 44, y: 8)); context?.addLine(to: CGPoint(x: 4, y: 8))
                context?.fillPath()
            default: context?.fill(r)
            }
            return context?.makeImage()
        }
        let frames = try [tile(0x34C759, 0), tile(0xFF9500, 1), tile(0xFF3B30, 2)].map { try #require($0) }
        let pack = MenuBarIconAnimation(id: "pack", frames: frames, durations: [1, 1, 1],
                                        statuses: [.up: 0..<1, .degraded: 1..<2, .down: 2..<3])
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            let rows = VStack(alignment: .leading, spacing: 6) {
                ForEach(panelScenarios, id: \.self) { s in
                    HStack(spacing: 20) {
                        ForEach([false, true], id: \.self) { quiet in
                            let m = { var m = item(s, quiet: quiet); m.icon = .custom; m.iconSize = 22; return m }()
                            Renderers.renderer(for: theme).statusItem(m, context: StatusItemContext(theme: theme, menuBarIsDark: true,
                                                                                                  customIcon: pack))
                        }
                    }
                }
            }
            try snapshot("item-pack-\(theme.id)", OnDesktop(dark: true, padding: 12) { rows })
        }
    }

    /// Quieted until it gets worse: the alerts' badges in the menu bar's
    /// ink, beside the same in color.
    @Test func quiet() throws {
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for dark in [true, false] {
                let rows = VStack(alignment: .leading, spacing: 0) {
                    ForEach([FixtureEngine.Scenario.degraded, .incidents], id: \.self) { s in
                        bar(dark: dark) {
                            ForEach(TopophanyKit.Settings.Appearance.Show.allCases, id: \.self) { show in
                                drawn(item(s, show: show), theme: theme, dark: dark)
                                drawn(item(s, show: show, quiet: true), theme: theme, dark: dark)
                            }
                        }
                    }
                }
                try snapshot("item-quiet-\(theme.id)-\(dark ? "dark" : "light")", OnDesktop(dark: dark, padding: 12) { rows })
            }
        }
    }

    /// This Mac's readings beside the item: each alone, all three, and all
    /// three before the first sample.
    @Test func readings() throws {
        let all: [TopophanyKit.Settings.Appearance.MenuBar.Reading] = [.cpu, .memory, .network]
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for dark in [true, false] {
                let rows = VStack(alignment: .trailing, spacing: 0) {
                    ForEach(all, id: \.self) { r in bar(dark: dark) { drawn(item(.clear, readings: [r]), theme: theme, dark: dark) } }
                    bar(dark: dark) { drawn(item(.incidents, readings: all), theme: theme, dark: dark) }
                    bar(dark: dark) { drawn(item(.degraded, colors: false, readings: all), theme: theme, dark: dark) }
                    bar(dark: dark) { drawn(item(.offline, readings: all, local: nil), theme: theme, dark: dark) }
                }
                try snapshot("item-readings-\(theme.id)-\(dark ? "dark" : "light")", OnDesktop(dark: dark, padding: 12) { rows })
            }
        }
    }

    /// One step of the turn in eight frames, then the rest pose; the
    /// spinner while `topo` starts.
    @Test func turn() throws {
        let blind = SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: snapshotOrigin), engine: .starting,
                                                    settings: previewSettings()))
        let starting = StatusItemModel(status: blind.status, appearance: .init())
        #expect(starting.activity == .connecting)
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for dark in [true, false] {
                let rows = VStack(alignment: .leading, spacing: 0) {
                    bar(dark: dark) {
                        ForEach(0..<8, id: \.self) { f in
                            drawn(item(.clear, show: .symbol), theme: theme, dark: dark, motion: .init(turn: Double(f) / 8))
                        }
                        drawn(item(.clear, show: .symbol), theme: theme, dark: dark)
                    }
                    bar(dark: dark) {
                        ForEach(0..<8, id: \.self) { f in
                            drawn(starting, theme: theme, dark: dark, motion: .init(time: Double(f) * 0.09))
                        }
                        drawn(starting, theme: theme, dark: dark)
                    }
                }
                try snapshot("item-turn-\(theme.id)-\(dark ? "dark" : "light")", OnDesktop(dark: dark, padding: 12) { rows })
            }
        }
    }

    /// Changes as they settle, a frame every 0.08 s: worse, more of the
    /// same, better, and words.
    @Test func changes() throws {
        let cases: [(StatusItemModel, StatusItemModel)] = [
            (item(.clear), item(.degraded)),
            (item(.degraded), item(.incidents)),
            (item(.incidents), item(.clear)),
            (item(.clear, show: .words), item(.incidents, show: .words)),
        ]
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            let rows = VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cases.enumerated()), id: \.offset) { _, c in
                    bar(dark: true) {
                        ForEach(0..<12, id: \.self) { f in
                            drawn(c.1, theme: theme, dark: true, motion: .init(change: .init(from: c.0, age: Double(f) * 0.08)))
                        }
                    }
                }
            }
            try snapshot("item-changes-\(theme.id)", OnDesktop(dark: true, padding: 12) { rows })
        }
    }
}
