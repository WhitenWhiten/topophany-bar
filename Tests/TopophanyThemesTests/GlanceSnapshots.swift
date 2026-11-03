import Foundation
import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// What Glance opens and what it folds, where its parts stand, and the
/// keyboard's order through them (DESIGN.md §8).
@MainActor
@Suite struct GlanceLayoutTests {
    init() { L10n.force("en") }

    func kinds(_ layout: GlanceLayout) -> [String] {
        layout.parts.map { part in
            switch part {
            case .card(let s): "card:" + s.id.rawValue
            case .places(let s): "places:" + s.map(\.id.rawValue).joined(separator: ",")
            case .lines(let s): "lines:" + s.map(\.id.rawValue).joined(separator: ",")
            }
        }
    }

    /// Calm, everything but the places folds into lines; Seen from is the
    /// hero's.
    @Test func calmFolds() {
        let layout = GlanceLayout(previewPanel(.clear))
        #expect(layout.seen != nil)
        #expect(kinds(layout) == ["places:map,fleet,zones", "lines:applications,mac"])
    }

    /// What needs a look opens where Settings puts it; the calm sections
    /// beside it stay lines. Nothing moves to the top.
    @Test func troubleOpensInPlace() {
        let layout = GlanceLayout(previewPanel(.incidents))
        #expect(kinds(layout) == ["card:attention", "places:map,fleet,zones", "card:applications", "lines:mac"])
        var settings = previewSettings(mac: .server)
        settings.sections.order = [.status, .mac, .zones, .applications, .seen, .attention, .fleet, .map]
        let moved = GlanceLayout(previewPanel(.incidents, settings: settings))
        #expect(kinds(moved).first == "lines:mac" || kinds(moved).first == "card:mac")
        #expect(kinds(moved).contains("places:zones,fleet,map"))
    }

    /// Unknown isn't trouble: offline, every section folds, its marks
    /// withheld rather than called up.
    @Test func unknownFolds() {
        let layout = GlanceLayout(previewPanel(.offline))
        #expect(!layout.parts.contains { if case .card = $0 { true } else { false } })
        guard case .lines(let lines)? = layout.parts.last, case .applications(let a)? = lines.first else {
            Issue.record("no applications line")
            return
        }
        #expect(!a.rows.contains { $0.mark == .up })
    }

    /// Pinned lists always open, as tiles.
    @Test func pinnedOpens() {
        let layout = GlanceLayout(previewPanel(.clear, settings: previewSettings(servers: true, services: true)))
        #expect(kinds(layout).contains("card:services"))
        #expect(kinds(layout).contains("card:servers"))
    }

    /// ↑ ↓ go as the panel is drawn: the hero's observers first, then each
    /// part, so a section Settings put above Seen from comes after it.
    @Test func focusFollowsTheLayout() {
        let model = previewPanel(.incidents)
        let order = GlanceRenderer().focusOrder(model)
        let seen = (model.seen?.problems ?? []).map { "seen:" + $0.id }
        #expect(!seen.isEmpty)
        #expect(Array(order.prefix(seen.count)) == seen)
        #expect(Set(order) == Set(Renderers.focusOrder(model)))
        let map = order.firstIndex(of: "map")
        let app = order.firstIndex { $0.hasPrefix("app:") }
        let attention = order.firstIndex { $0.hasPrefix("attention:") }
        #expect(attention! < map! && map! < app!)
        // A renderer that keeps the sections' order keeps theirs.
        #expect(CardsRenderer().focusOrder(model) == Renderers.focusOrder(model))
    }

    /// The keyboard's focus on a row of a folded section opens its line.
    @Test func focusOpensALine() throws {
        let model = previewPanel(.clear)
        let apps = try #require(model.applications)
        let section = PanelModel.Section.applications(apps)
        #expect(GlanceLines.holds(section, "app:" + apps.rows[0].id))
        #expect(!GlanceLines.holds(section, "map"))
        #expect(!GlanceLines.holds(section, nil))
    }

    /// A line's readings give way a part at a time, never a number cut.
    @Test func linesShorten() {
        let local = LocalSection(model: "Mac", readings: [.cpu, .memory, .storage], snapshot: sampleLocal)
        #expect(GlanceLine.readings(local) == ["CPU 17% · Memory 72% · Storage 44%", "CPU 17% · Memory 72%", "CPU 17%"])
    }
}

/// Glance: the panel in each state, light and dark; pinned items as tiles;
/// lines opened; the places' lenses; scrolling; the Status widget's dial
/// in every size and state; and in Japanese and Chinese.
@MainActor
@Suite(.serialized) struct GlanceSnapshots {
    init() { L10n.force("en") }

    func panel(_ model: PanelModel, dark: Bool, maxHeight: Double? = nil, focus: String? = nil,
               textSize: TopophanyKit.Settings.Appearance.TextSize = .default, opened: Set<SectionID> = []) -> some View {
        let ctx = RenderContext(theme: ThemeStore.glance, colorScheme: dark ? .dark : .light, textSize: textSize, focus: focus,
                                maxHeight: maxHeight)
        return OnDesktop(dark: dark) { GlancePanel(model: model, ctx: ctx, opened: opened) }
    }

    @Test func panels() throws {
        for s in panelScenarios {
            for dark in [true, false] {
                let size = try snapshot("panel-glance-\(dark ? "dark" : "light")-\(s.rawValue)", panel(previewPanel(s), dark: dark))
                #expect(abs(size.width - 392) < 0.5, "\(size)")
            }
        }
        // Shorter than Native's, every state: it folds what's calm.
        for s in panelScenarios {
            let model = previewPanel(s)
            let glance = try snapshot("panel-glance-compare-\(s.rawValue)", panel(model, dark: true))
            let native = try snapshot("panel-native-compare-\(s.rawValue)", OnDesktop(dark: true) {
                CardsRenderer().panel(model, context: RenderContext(theme: ThemeStore.native, colorScheme: .dark))
            })
            #expect(glance.height < native.height * 0.75, "\(s): \(glance.height) against \(native.height)")
        }
    }

    /// Pinned services, checks and servers as tiles; then one of each open.
    @Test func pinned() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/Monitoring/preview.ndjson")
        let f = try #require(FrameDecoder.frame(from: Data(contentsOf: url)))
        let now = try #require(f.generatedAt)
        var policy = ReaderPolicy()
        policy.receive(f, at: now)
        let pins: [MonitorPin] = [.init(kind: .check, id: "m-clash"), .init(kind: .link, id: "home-cf")]
        func model(expanded: Set<MonitorPin>) -> PanelModel {
            var m = previewPanel(.incidents, settings: previewSettings(servers: true, services: true))
            let monitors = SectionBuilder.monitors(policy.evaluate(at: now), pins: pins, expanded: expanded)
            m.sections = m.sections.map { s in
                if case .services(let cards) = s { return .services(cards + monitors) }
                return s
            }
            return m
        }
        let tiles = model(expanded: [])
        for dark in [true, false] {
            try snapshot("panel-glance-\(dark ? "dark" : "light")-pinned", panel(tiles, dark: dark))
        }
        // A check opens by its own disclosure; a service and a server by
        // a click, as `opened` leaves them.
        let open = model(expanded: [pins[0]])
        let ctx = RenderContext(theme: ThemeStore.glance, colorScheme: .dark, focus: "server:bwh-la")
        let p = CardsPalette.resolve(ctx)
        let t = CardsType(scale: 1, theme: ThemeStore.glance)
        try snapshot("pinned-glance-dark-open", OnDesktop(dark: true) {
            VStack(spacing: 6) {
                GlancePinned(title: "Pinned", meta: "4 pinned", items: open.services.map { .service($0) }, p: p, t: t, focus: nil,
                             opened: ["service:vless-entry"])
                GlancePinned(title: "Servers", meta: "2 pinned", items: open.servers.map { .server($0) }, p: p, t: t,
                             focus: "server:bwh-la", opened: ["server:oracle-ny"])
            }
            .padding(8).frame(width: 344)
            .background { CardsPanelBackground(ctx: ctx, p: p, radius: 18) }
            .environment(\.colorScheme, .dark)
        })
    }

    /// Lines a click opened, and one the keyboard's focus opened; This Mac
    /// as a server, calm and in trouble.
    @Test func lines() throws {
        let clear = previewPanel(.clear)
        try snapshot("panel-glance-dark-clear-open", panel(clear, dark: true, opened: [.applications, .mac]))
        let app = try #require(clear.applications?.rows[1].id)
        try snapshot("panel-glance-light-clear-focus", panel(clear, dark: false, focus: "app:" + app))
        let server = previewSettings(mac: .server)
        try snapshot("panel-glance-dark-clear-server", panel(previewPanel(.clear, settings: server), dark: true, opened: [.mac]))
        try snapshot("panel-glance-light-incidents-server", panel(previewPanel(.incidents, settings: server), dark: false))
    }

    /// Each lens, and the keyboard's focus on the map showing it.
    @Test func places() throws {
        let model = previewPanel(.incidents)
        let ctx = RenderContext(theme: ThemeStore.glance, colorScheme: .dark)
        let p = CardsPalette.resolve(ctx)
        let t = CardsType(scale: 1, theme: ThemeStore.glance)
        let sections = model.sections.filter { [.map, .fleet, .zones].contains($0.id) }
        for lens in [SectionID.fleet, .zones] {
            try snapshot("places-glance-dark-\(lens.rawValue)", OnDesktop(dark: true) {
                GlancePlaces(sections: sections, p: p, t: t, mapFocused: false, lens: lens)
                    .padding(8).frame(width: 344)
                    .background { CardsPanelBackground(ctx: ctx, p: p, radius: 18) }
                    .environment(\.colorScheme, .dark)
            })
        }
        try snapshot("places-glance-dark-map-focused", OnDesktop(dark: true) {
            GlancePlaces(sections: sections, p: p, t: t, mapFocused: true, lens: .zones)
                .padding(8).frame(width: 344)
                .background { CardsPanelBackground(ctx: ctx, p: p, radius: 18) }
                .environment(\.colorScheme, .dark)
        })
        // One of them alone has no lenses, only its title.
        try snapshot("places-glance-light-zones-alone", OnDesktop(dark: false) {
            GlancePlaces(sections: sections.filter { $0.id == .zones }, p: CardsPalette.resolve(RenderContext(theme: ThemeStore.glance, colorScheme: .light)),
                         t: t, mapFocused: false)
                .padding(8).frame(width: 344)
                .environment(\.colorScheme, .light)
        })
    }

    /// Taller than the screen allows: the hero stays and the rest scrolls,
    /// within the height given; and the shortest panel.
    @Test func scrolling() throws {
        let tall = previewPanel(.incidents, settings: previewSettings(servers: true, limit: 5, services: true))
        for dark in [true, false] {
            let size = try snapshot("panel-glance-\(dark ? "dark" : "light")-incidents-scrolling", panel(tall, dark: dark, maxHeight: 700))
            #expect(size.height <= 700 + 48 + 0.5, "\(size)")
        }
        try snapshot("panel-glance-dark-shortest", panel(previewPanel(.incidents).shortest, dark: true))
    }

    /// Small and large text: the verdict and the lines keep whole.
    @Test func textSizes() throws {
        for size in [TopophanyKit.Settings.Appearance.TextSize.small, .large] {
            try snapshot("panel-glance-dark-incomplete-\(size.rawValue)", panel(previewPanel(.incomplete), dark: true, textSize: size))
            try snapshot("panel-glance-light-clear-\(size.rawValue)", panel(previewPanel(.clear), dark: false, textSize: size,
                                                                            opened: [.mac]))
        }
    }

    @Test(arguments: ["ja", "zh-Hans"])
    func language(_ l: String) throws {
        try L10n.with(l) {
            try snapshot("i18n-\(l)-panel-glance", panel(previewPanel(.incidents, settings: previewSettings(servers: true)), dark: true))
            try snapshot("i18n-\(l)-panel-glance-clear", panel(previewPanel(.clear), dark: false))
            let w = WidgetModel(kind: .status, panel: previewPanel(.incidents, settings: previewSettings(mac: .off, servers: true)))
            try snapshot("i18n-\(l)-widget-glance-s", onDesktop(w, .small, theme: ThemeStore.glance, dark: true))
            try snapshot("i18n-\(l)-widget-glance-l", onDesktop(w, .large, theme: ThemeStore.glance, dark: false))
        }
    }

    func status(_ s: FixtureEngine.Scenario) -> WidgetModel {
        WidgetModel(kind: .status, panel: previewPanel(s, settings: previewSettings(mac: .off, servers: true)))
    }

    /// The Status widget in every size, light and dark, at the design's
    /// size and WidgetKit's smaller one; every state small; in one tone;
    /// not current.
    @Test func widgets() throws {
        for dark in [true, false] {
            let a = dark ? "dark" : "light"
            for (size, n) in WidgetSnapshots.sizes {
                let s = try snapshot("widget-glance-\(a)-status-\(n)", onDesktop(status(.incidents), size, theme: ThemeStore.glance, dark: dark))
                #expect(abs(s.width - (size.width + 48)) < 0.5 && abs(s.height - (size.height + 48)) < 0.5, "\(n): \(s)")
                let b = try #require(WidgetSnapshots.smaller[size])
                try snapshot("widget-glance-\(a)-status-\(n)-1080", onDesktop(status(.incidents), size, bounds: b, theme: ThemeStore.glance, dark: dark))
            }
        }
        for s in panelScenarios {
            try snapshot("widget-glance-state-\(s.rawValue)", onDesktop(status(s), .small, theme: ThemeStore.glance, dark: true))
        }
        try snapshot("widget-glance-dark-status-m-clear", onDesktop(status(.clear), .medium, theme: ThemeStore.glance, dark: true))
        try snapshot("widget-glance-light-status-xl-clear", onDesktop(status(.clear), .extraLarge, theme: ThemeStore.glance, dark: false))
        for (size, n) in [(WidgetSize.small, "s"), (.large, "l")] {
            try snapshot("widget-glance-vibrant-status-\(n)", onDesktop(status(.incidents), size, theme: ThemeStore.glance, dark: true,
                                                                        rendering: .vibrant))
        }
        let stale = status(.incidents).notCurrent(at: snapshotOrigin.addingTimeInterval(47 * 60))
        try snapshot("widget-glance-state-not-current", onDesktop(stale, .small, theme: ThemeStore.glance, dark: true))
        // Every other kind is Native's, its titles without their symbols.
        let server = WidgetModel(kind: .server(node: "oracle-ny", isMac: false),
                                 panel: previewPanel(.incidents, settings: previewSettings(mac: .server, servers: true)))
        try snapshot("widget-glance-dark-server-m", onDesktop(server, .medium, theme: ThemeStore.glance, dark: true))
        let zones = WidgetModel(kind: .zones, panel: previewPanel(.incidents))
        try snapshot("widget-glance-light-zones-l", onDesktop(zones, .large, theme: ThemeStore.glance, dark: false))
    }

    /// A dial holds every check: a tick each while they can be told apart,
    /// runs of color past that.
    @Test func dials() throws {
        let ctx = RenderContext(theme: ThemeStore.glance, colorScheme: .dark)
        let p = CardsPalette.resolve(ctx)
        let counts: [(Int, Int, Int, Int)] = [(68, 0, 0, 0), (60, 2, 5, 1), (8, 1, 1, 2), (480, 12, 30, 9)]
        try snapshot("dial-glance-dark", OnDesktop(dark: true) {
            HStack(spacing: 16) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, c in
                    DialRing(counts: (c.0, c.1, c.2, c.3), p: p).frame(width: 74, height: 74)
                }
                DialRing(counts: nil, p: p).frame(width: 74, height: 74)
            }
        })
    }
}
