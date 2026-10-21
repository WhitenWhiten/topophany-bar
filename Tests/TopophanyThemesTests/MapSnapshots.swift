import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// The map, in every theme, framing and state; magnified; and its
/// widgets.
@MainActor
@Suite(.serialized) struct MapSnapshots {
    init() { L10n.force("en") }

    func mapSettings(_ frame: Sections.MapFrame = .fit) -> TopophanyKit.Settings {
        var s = previewSettings()
        s.sections.mapFrame = frame
        return s
    }

    func panel(_ scenario: FixtureEngine.Scenario, _ frame: Sections.MapFrame = .fit) -> PanelModel {
        let s = mapSettings(frame)
        let request = TemplateCompiler().request(for: s, revision: 1, listServers: true, serviceCards: true, listServices: true,
                                                 mapGraph: true)
        let reading = FixtureEngine.reading(scenario, request: request, origin: snapshotOrigin, after: 4)
        return SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: s, local: sampleLocal, here: snapshotHere))
    }

    func card(_ m: MapSection, theme: Theme, dark: Bool, viewport: MapViewport? = nil) -> some View {
        let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
        let p = CardsPalette.resolve(ctx)
        return OnDesktop(dark: dark) {
            CardsMapCard(map: m, p: p, t: CardsType(scale: 1, theme: theme), focused: false)
                .environment(\.mapViewport, viewport)
                .padding(8)
                .frame(width: 344)
                .background { CardsPanelBackground(ctx: ctx, p: p, radius: p.style.panelRadius) }
                .environment(\.colorScheme, dark ? .dark : .light)
        }
    }

    @Test func nativeCard() throws {
        for dark in [true, false] {
            let a = dark ? "dark" : "light"
            for s in [FixtureEngine.Scenario.incidents, .clear] {
                let m = try #require(panel(s).map)
                try snapshot("map-native-\(a)-\(s.rawValue)", card(m, theme: ThemeStore.native, dark: dark))
            }
        }
    }

    /// Aurora and Linen, as Native's card looks in each.
    @Test func cardThemes() throws {
        for id in ["aurora", "linen"] {
            for dark in [true, false] {
                let theme = ThemeStore().theme(id)
                try snapshot("map-\(id)-\(dark ? "dark" : "light")-incidents", card(try #require(panel(.incidents).map), theme: theme, dark: dark))
            }
        }
        // Magnified, as the pointer leaves it.
        let v = MapViewport()
        v.layout(CGSize(width: 344, height: 172))
        v.zoom(by: 2.5, at: CGPoint(x: 130, y: 90))
        try snapshot("map-native-dark-zoomed", card(try #require(panel(.incidents).map), theme: ThemeStore.native, dark: true, viewport: v))
        v.isSelected = true
        try snapshot("map-native-light-selected", card(try #require(panel(.incidents).map), theme: ThemeStore.native, dark: false, viewport: v))
        // Without map.graph: placed by name, with no lines.
        let s = mapSettings()
        let request = TemplateCompiler().request(for: s, revision: 1, listServers: true, serviceCards: true, listServices: true)
        let reading = FixtureEngine.reading(.incidents, request: request, origin: snapshotOrigin, after: 4)
        let byName = SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: s, local: sampleLocal, here: snapshotHere))
        try snapshot("map-native-dark-by-name", card(try #require(byName.map), theme: ThemeStore.native, dark: true))
    }

    func whole(_ m: PanelModel, theme: Theme, dark: Bool) -> some View {
        let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
        return OnDesktop(dark: dark || theme.renderer == .cells) { Renderers.renderer(for: theme).panel(m, context: ctx) }
    }

    @Test func cellsPanels() throws {
        for theme in [ThemeStore.terminal, ThemeStore().theme("paper"), ThemeStore().theme("dusk")] {
            try snapshot("map-panel-\(theme.id)-incidents", whole(panel(.incidents), theme: theme, dark: true))
        }
        try snapshot("map-panel-terminal-world-clear", whole(panel(.clear, .world), theme: ThemeStore.terminal, dark: true))
    }

    func widget(_ scenario: FixtureEngine.Scenario, _ frame: Sections.MapFrame = .fit) -> WidgetModel {
        WidgetModel(kind: .map(frame: frame), panel: panel(scenario))
    }

    @Test func widgets() throws {
        for (size, n) in WidgetSnapshots.sizes {
            for dark in [true, false] {
                try snapshot("map-widget-native-\(dark ? "dark" : "light")-\(n)", onDesktop(widget(.incidents), size, theme: ThemeStore.native, dark: dark))
            }
            try snapshot("map-widget-terminal-\(n)", onDesktop(widget(.incidents), size, theme: ThemeStore.terminal, dark: true))
            let small = try #require(WidgetSnapshots.smaller[size])
            try snapshot("map-widget-native-light-\(n)-1080", onDesktop(widget(.incidents), size, bounds: small, theme: ThemeStore.native, dark: false))
            try snapshot("map-widget-paper-\(n)-1080", onDesktop(widget(.degraded), size, bounds: small, theme: ThemeStore().theme("paper"), dark: false))
        }
        try snapshot("map-widget-native-vibrant-l", onDesktop(widget(.incidents), .large, theme: ThemeStore.native, dark: true, rendering: .vibrant))
        try snapshot("map-widget-native-world-xl", onDesktop(widget(.clear, .world), .extraLarge, theme: ThemeStore.native, dark: true))
        let stale = widget(.incidents).notCurrent(at: snapshotOrigin.addingTimeInterval(47 * 60))
        try snapshot("map-widget-native-not-current-m", onDesktop(stale, .medium, theme: ThemeStore.native, dark: true))
    }
}
