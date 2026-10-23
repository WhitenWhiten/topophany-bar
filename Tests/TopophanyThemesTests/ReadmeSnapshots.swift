import Foundation
import ImageIO
import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes
import UniformTypeIdentifiers

/// The README's illustrations, rendered directly from the panel, widget and
/// menu bar views with fixed English demo data and a fixed clock.
@MainActor
@Suite(.serialized) struct ReadmeSnapshots {
    typealias MenuBarSettings = TopophanyKit.Settings.Appearance.MenuBar

    init() { L10n.force("en") }

    // MARK: pieces

    /// A widget as the desktop shows it.
    func tile(_ model: WidgetModel, _ size: WidgetSize, theme: Theme, dark: Bool = true) -> some View {
        let context = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
        let renderer = Renderers.renderer(for: theme)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return renderer.widget(model, size: size, bounds: CGSize(width: size.width, height: size.height), context: context)
            .background(renderer.widgetBackground(context: context))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.18 : 0.7), lineWidth: 0.5))
            .compositingGroup()
            .shadow(color: .black.opacity(0.28), radius: 14, y: 9)
    }

    /// A panel as it opens, with its window's shadow.
    func panel(_ model: PanelModel, theme: Theme, dark: Bool = true) -> some View {
        Renderers.renderer(for: theme).panel(model, context: RenderContext(theme: theme, colorScheme: dark ? .dark : .light))
            .fixedSize()
            .transaction { $0.disablesAnimations = true }
            .compositingGroup()
            .shadow(color: .black.opacity(0.4), radius: 24, y: 14)
    }

    /// A view's size, in points.
    func measure(_ view: some View) throws -> CGSize {
        let renderer = ImageRenderer(content: view.fixedSize())
        let image = try #require(renderer.cgImage)
        return CGSize(width: Double(image.width), height: Double(image.height))
    }

    func item(_ scenario: FixtureEngine.Scenario, icon: MenuBarSettings.Icon = .whiteNight,
              show: TopophanyKit.Settings.Appearance.Show = .count, readings: [MenuBarSettings.Reading] = []) -> StatusItemModel {
        var a = MenuBarSettings()
        a.show = show
        a.icon = icon
        a.readings = readings
        return StatusItemModel(status: previewPanel(scenario).status, appearance: a, local: sampleLocal)
    }

    /// The item on a dark menu bar, its sky `time` seconds into its drift.
    func drawn(_ model: StatusItemModel, theme: Theme = ThemeStore.native, time: Double = 6,
               change: StatusItemMotion.Change? = nil, portrait: MenuBarIconAnimation? = nil) -> some View {
        Renderers.renderer(for: theme).statusItem(model, context: StatusItemContext(
            theme: theme, menuBarIsDark: true, motion: StatusItemMotion(moves: true, time: time, change: change), portrait: portrait))
    }

    /// The system's own items at the menu bar's right end.
    var systemItems: some View {
        HStack(spacing: 18) {
            Image(systemName: "wifi")
            Image(systemName: "switch.2")
            Text("Fri Oct 23  9:41")
        }
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(.white)
        .fixedSize()
    }

    // MARK: hero

    /// White Night in the menu bar, the panel open beneath it, and widgets
    /// on the desktop.
    @Test func hero() throws {
        var settings = previewSettings(mac: .off)
        settings.sections.applications = false
        settings.sections.fleet = false
        settings.sections.zones = false
        let model = previewPanel(.degraded, settings: settings)
        let widgets = previewPanel(.degraded, settings: previewSettings(mac: .off, servers: true, services: true))
        let native = ThemeStore.native
        let panelSize = try measure(Renderers.renderer(for: native).panel(model, context: RenderContext(theme: native, colorScheme: .dark)))
        let bar = 34.0, width = 1280.0
        let widgetsHeight = WidgetSize.large.height + 24 + WidgetSize.medium.height
        let height = max(bar + 8 + panelSize.height, bar + 48 + widgetsHeight) + 44

        let desktop = VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 24) {
                tile(WidgetModel(kind: .status, panel: widgets), .large, theme: native)
                VStack(spacing: 24) {
                    tile(WidgetModel(kind: .server(node: "oracle-ny", isMac: false), panel: widgets), .medium, theme: native)
                    tile(WidgetModel(kind: .zones, panel: widgets), .medium, theme: native)
                }
            }
            HStack(spacing: 24) {
                tile(WidgetModel(kind: .service(id: "vless-entry"), panel: widgets), .medium, theme: native)
                tile(MapSnapshots().widget(.degraded), .medium, theme: native)
            }
        }

        // The panel centers on the item, as PanelController places it.
        let item = drawn(item(.degraded))
            .overlay(alignment: .top) {
                // The item is 26 points tall in the middle of the bar.
                panel(model, theme: native).offset(y: (bar + 26) / 2 + 6)
            }
        try snapshot("readme-hero", opaque: true, ZStack(alignment: .topLeading) {
            Wallpaper(dark: true)
            desktop.padding(.leading, 40).padding(.top, bar + 48)
            HStack(spacing: 22) {
                Spacer(minLength: 0)
                item
                systemItems
            }
            .padding(.horizontal, 16)
            .frame(width: width, height: bar)
            .background(Color.black.opacity(0.22))
        }
        .frame(width: width, height: height))
    }

    // MARK: menu bar

    /// A stretch of dark menu bar.
    func strip(_ content: some View) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.32)))
    }

    /// Each status as White Night, the globe and Terminal's chip show it,
    /// then This Mac's readings beside the item.
    @Test func menuBar() throws {
        let statuses: [(FixtureEngine.Scenario, String)] = [
            (.clear, "All clear"), (.degraded, "Degraded"), (.incidents, "Down"), (.incomplete, "Incomplete"), (.offline, "Offline"),
        ]
        let styles: [(String, (FixtureEngine.Scenario) -> AnyView)] = [
            ("White Night", { AnyView(self.drawn(self.item($0))) }),
            ("Globe", { AnyView(self.drawn(self.item($0, icon: .globe))) }),
            ("Terminal", { AnyView(self.drawn(self.item($0, icon: .globe, show: .words), theme: ThemeStore.terminal)) }),
        ]
        let caption = Font.system(size: 12.5, weight: .semibold)
        let sheet = Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(statuses.indices, id: \.self) { i in
                        Text(statuses[i].1).font(caption).foregroundStyle(.white.opacity(0.7)).padding(.leading, 4)
                    }
                }
                ForEach(styles.indices, id: \.self) { row in
                    GridRow {
                        Text(styles[row].0).font(caption).foregroundStyle(.white.opacity(0.85))
                        ForEach(statuses.indices, id: \.self) { i in strip(styles[row].1(statuses[i].0)) }
                    }
                }
                GridRow {
                    Text("This Mac").font(caption).foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 12) {
                        strip(drawn(item(.clear, readings: [.cpu, .memory, .network])))
                        strip(drawn(item(.degraded, icon: .globe, readings: [.cpu, .memory])))
                    }
                    .gridCellColumns(statuses.count)
                }
                .padding(.top, 8)
        }
        try snapshot("readme-menu-bar", scale: 4, opaque: true, OnDesktop(dark: true, padding: 24) { sheet })
    }

    /// White Night over 24 seconds, the sky's own loop: clear, degraded,
    /// down, and clear again. Each moon dissolves through the dither as
    /// the app plays it, and the words roll.
    @Test func whiteNightAnimation() throws {
        let sky = try #require(MenuBarIconAnimation.whiteNight(pixelHeight: 48))
        let acts: [(at: Double, model: StatusItemModel)] = [
            (0, item(.clear, show: .words)), (6, item(.degraded, show: .words)),
            (12, item(.incidents, show: .words)), (18, item(.clear, show: .words)),
        ]
        // In GIF's hundredths of a second: the sky's own frames, and finer
        // steps while a change settles.
        let settling = Int(StatusItemMotion.changeLength * 100)
        func settles(_ cs: Int) -> Bool { acts.dropFirst().contains { cs >= Int($0.at * 100) && cs < Int($0.at * 100) + settling } }
        let drift = (0..<sky.frames.count).map { Int((Double($0) * sky.duration / Double(sky.frames.count) * 100).rounded()) }
        let changes = acts.dropFirst().flatMap { a in stride(from: 0, to: settling, by: 6).map { Int(a.at * 100) + $0 } }
        let times = Set(drift.filter { !settles($0) } + changes).sorted()
        var frames: [(CGImage, Double)] = []
        for (i, cs) in times.enumerated() {
            let t = Double(cs) / 100
            let n = try #require(acts.lastIndex { $0.at <= t })
            let model = acts[n].model, age = t - acts[n].at
            var portrait = sky
            var change: StatusItemMotion.Change?
            if n > 0, age < StatusItemMotion.changeLength {
                change = .init(from: acts[n - 1].model, age: age)
                let from = sky.overlays[acts[n - 1].model.mark]?.color, to = sky.overlays[model.mark]?.color
                let steps = MenuBarIconAnimation.dissolve(from: from, to: to)
                // The app plays the steps over 0.48 s.
                let k = Int(age / (0.48 / Double(steps.count)))
                if k < steps.count { portrait.overlays[model.mark] = .init(color: steps[k], ink: steps[k]) }
            }
            let bar = HStack(spacing: 22) {
                Spacer(minLength: 0)
                drawn(model, time: t, change: change, portrait: portrait)
                systemItems
            }
            .padding(.horizontal, 16)
            .frame(width: 400, height: 34)
            .background(Color(rgb: 0x161B2C))
            let renderer = ImageRenderer(content: bar)
            // Each of the sky's dots on 2 × 2 pixels.
            renderer.scale = 4
            let delay = Double((i + 1 < times.count ? times[i + 1] : 2400) - cs) / 100
            frames.append((try #require(renderer.cgImage, "frame \(i)"), delay))
        }
        let url = snapshotDirectory.appending(path: "readme-white-night.gif")
        let gif = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil))
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, delay) in frames {
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay,
            ]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(gif))
    }

    // MARK: direct

    /// A profile that reads a Beszel Hub and a Komari server directly, with
    /// the servers named `pinned` pinned in that order.
    func direct(pinned: [String]) throws -> PanelModel {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/DirectDevelopment/mixed.json")
        let now = try #require(Timestamp.parse("2026-10-21T12:00:00Z"))
        let data = try Data(contentsOf: url)
        let frame = try #require(FrameDecoder.frame(from: data))
        var policy = ReaderPolicy()
        policy.receive(frame, line: data, at: now)
        func panel(_ nodes: [String]) -> PanelModel {
            var s = TopophanyKit.Settings()
            s.topo.source = "direct"
            s.sections.servers = true
            s.sections.mac.mode = .off
            s.sections.serverNodes = nodes
            return SectionBuilder.panel(.init(reading: policy.evaluate(at: now), engine: .running, settings: s))
        }
        let all = panel(frame.rows.compactMap(\.select?.node))
        let nodes = pinned.compactMap { name in all.servers.first { $0.name == name }?.id }
        #expect(nodes.count == pinned.count)
        return panel(nodes)
    }

    @Test func directSources() throws {
        let model = try direct(pinned: ["nas", "tokyo-2"])
        let widgets = try direct(pinned: ["nas", "pi-hole", "hk-1", "tokyo-2"])
        let tokyo = try #require(widgets.servers.first { $0.name == "tokyo-2" })
        try snapshot("readme-direct", opaque: true, OnDesktop(dark: true, padding: 32) {
            HStack(alignment: .top, spacing: 32) {
                panel(model, theme: ThemeStore.native)
                VStack(spacing: 24) {
                    tile(WidgetModel(kind: .status, panel: widgets), .large, theme: ThemeStore.native)
                    tile(WidgetModel(kind: .server(node: tokyo.id, isMac: false), panel: widgets), .medium, theme: ThemeStore.native)
                }
            }
        })
    }

    // MARK: themes

    /// Each built-in theme's panel: the status, what needs attention and
    /// This Mac, where each theme draws its own meters.
    @Test func themes() throws {
        var settings = previewSettings(mac: .local)
        settings.sections.seen = false
        settings.sections.map = false
        settings.sections.applications = false
        settings.sections.fleet = false
        settings.sections.zones = false
        let model = previewPanel(.incidents, settings: settings)
        let rows: [[(Theme, Bool)]] = [
            [(ThemeStore.native, true), (ThemeStore.aurora, true), (ThemeStore.linen, false)],
            [(ThemeStore.terminal, true), (ThemeStore.paper, false), (ThemeStore.dusk, true)],
        ]
        try snapshot("readme-themes", opaque: true, OnDesktop(dark: true, padding: 32) {
            VStack(spacing: 32) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(alignment: .top, spacing: 28) {
                        ForEach(rows[r].indices, id: \.self) { c in
                            let (theme, dark) = rows[r][c]
                            VStack(alignment: .leading, spacing: 12) {
                                Text(theme.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.leading, 10)
                                panel(model, theme: theme, dark: dark)
                            }
                        }
                    }
                }
            }
        })
    }

    // MARK: widgets

    @Test func widgetGallery() throws {
        let panel = previewPanel(.clear, settings: previewSettings(mac: .off, servers: true, services: true))
        let status = WidgetModel(kind: .status, panel: panel)
        let server = WidgetModel(kind: .server(node: "oracle-ny", isMac: false), panel: panel)
        let service = WidgetModel(kind: .service(id: "vless-entry"), panel: panel)
        let zones = WidgetModel(kind: .zones, panel: panel)
        let map = MapSnapshots().widget(.clear)

        try snapshot("readme-widgets", opaque: true, OnDesktop(dark: true, padding: 32) {
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 24) {
                    tile(status, .large, theme: ThemeStore.native)
                    tile(status, .medium, theme: ThemeStore.terminal)
                }
                VStack(spacing: 24) {
                    tile(map, .medium, theme: ThemeStore.native)
                    tile(server, .medium, theme: ThemeStore.aurora)
                    HStack(spacing: 24) {
                        tile(service, .small, theme: ThemeStore.paper, dark: false)
                        tile(zones, .small, theme: ThemeStore.paper, dark: false)
                    }
                }
                VStack(spacing: 24) {
                    tile(zones, .medium, theme: ThemeStore.native)
                    tile(service, .medium, theme: ThemeStore.linen, dark: false)
                    HStack(spacing: 24) {
                        tile(status, .small, theme: ThemeStore.dusk)
                        tile(server, .small, theme: ThemeStore.dusk)
                    }
                }
            }
        })
    }
}
