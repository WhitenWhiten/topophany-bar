import AppIntents
import SwiftUI
import TopophanyKit
import TopophanySections
import TopophanyThemes
import TopophanyWidgets
import WidgetKit

/// The widget extension: a thin wrapper that reads the app's hand-off and
/// draws it with the theme's renderer (DESIGN.md §7).
@main
struct TopophanyWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        ServerWidget()
        ServiceWidget()
        ZonesWidget()
    }
}

// MARK: configuration

/// The menu bar's theme, or a built-in one by its ID.
enum ThemeChoice: String, AppEnum {
    case bar, native, aurora, linen, terminal, paper, dusk

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Theme"
    static let caseDisplayRepresentations: [ThemeChoice: DisplayRepresentation] = [
        .bar: "Same as the Menu Bar",
        .native: "Native",
        .aurora: "Aurora",
        .linen: "Linen",
        .terminal: "Terminal",
        .paper: "Paper",
        .dusk: "Dusk",
    ]
}

enum RightChoice: String, AppEnum {
    case automatic, attention, applications

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Right Side"
    static let caseDisplayRepresentations: [RightChoice: DisplayRepresentation] = [
        .automatic: "Needs Attention, or Applications When Nothing Does",
        .attention: "Needs Attention",
        .applications: "Applications",
    ]

    var model: WidgetModel.Right {
        switch self {
        case .automatic: .automatic
        case .attention: .attention
        case .applications: .applications
        }
    }
}

struct StatusWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Status"
    static let description = IntentDescription("The verdict, and more of the panel as the size allows.")

    @Parameter(title: "Right Side", default: .automatic)
    var right: RightChoice

    @Parameter(title: "Theme", default: .bar)
    var theme: ThemeChoice
}

/// A server a widget can show: This Mac's node, the panel's pinned servers,
/// then every other server `topo` lists, by the names it last sent.
struct NodeEntity: AppEntity {
    var id: String
    var name: String
    var isMac: Bool

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Server"
    static let defaultQuery = NodeQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: isMac ? "This Mac · \(id)" : "\(id)")
    }
}

struct NodeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [NodeEntity] {
        let all = Self.known()
        return identifiers.map { id in all.first { $0.id == id } ?? NodeEntity(id: id, name: id, isMac: false) }
    }

    func suggestedEntities() async throws -> [NodeEntity] { Self.known() }

    func defaultResult() async -> NodeEntity? { Self.known().first }

    static func known() -> [NodeEntity] {
        guard let h = HandoffStore(appGroup: HandoffStore.bundleAppGroup).read() else { return [] }
        let s = h.decodedSettings.sections
        let panel = h.panel()
        var out: [NodeEntity] = []
        if !s.mac.node.isEmpty {
            let name = if case .server(let c, _)? = panel.mac, !c.isMissing { c.name } else { s.mac.node }
            out.append(NodeEntity(id: s.mac.node, name: name, isMac: true))
        }
        let listed = h.servers()
        for node in s.serverNodes where !out.contains(where: { $0.id == node }) {
            let name = panel.servers.first { $0.id == node && !$0.isMissing }?.name ?? listed.first { $0.id == node }?.name ?? node
            out.append(NodeEntity(id: node, name: name, isMac: false))
        }
        for server in listed where !out.contains(where: { $0.id == server.id }) {
            out.append(NodeEntity(id: server.id, name: server.name, isMac: false))
        }
        return out
    }
}

struct ServerWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Server"
    static let description = IntentDescription("One server's card: CPU, memory and disk against its limits.")

    @Parameter(title: "Server")
    var node: NodeEntity?

    @Parameter(title: "Theme", default: .bar)
    var theme: ThemeChoice
}

/// A service a widget can show: the panel's pinned services, then every
/// other service `topo` lists, by the names it last sent.
struct ServiceEntity: AppEntity {
    var id: String
    var name: String
    var application: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Service"
    static let defaultQuery = ServiceQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: application.isEmpty ? "\(id)" : "\(application) · \(id)")
    }
}

struct ServiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ServiceEntity] {
        let all = Self.known()
        return identifiers.map { id in all.first { $0.id == id } ?? ServiceEntity(id: id, name: id, application: "") }
    }

    func suggestedEntities() async throws -> [ServiceEntity] { Self.known() }

    func defaultResult() async -> ServiceEntity? { Self.known().first }

    static func known() -> [ServiceEntity] {
        guard let h = HandoffStore(appGroup: HandoffStore.bundleAppGroup).read() else { return [] }
        let s = h.decodedSettings.sections
        let panel = h.panel()
        let listed = h.services()
        var out: [ServiceEntity] = []
        for id in s.serviceIDs where !out.contains(where: { $0.id == id }) {
            let card = panel.services.first { $0.id == id && !$0.isMissing }
            let entry = listed.first { $0.id == id }
            out.append(ServiceEntity(id: id, name: card?.name ?? entry?.name ?? id, application: card?.application ?? entry?.application ?? ""))
        }
        for service in listed where !out.contains(where: { $0.id == service.id }) {
            out.append(ServiceEntity(id: service.id, name: service.name, application: service.application))
        }
        return out
    }
}

struct ServiceWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Service"
    static let description = IntentDescription("One service's card: who sees it from where, and how fast it answered.")

    @Parameter(title: "Service")
    var service: ServiceEntity?

    @Parameter(title: "Theme", default: .bar)
    var theme: ThemeChoice
}

struct ZonesWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Time Zones"
    static let description = IntentDescription("The time where your servers are, and each one’s health.")

    @Parameter(title: "Theme", default: .bar)
    var theme: ThemeChoice
}

// MARK: timeline

struct Entry: TimelineEntry {
    var date: Date
    var model: WidgetModel
    var theme: Theme
}

/// Entries from the hand-off: now, then not current at the next heartbeat
/// plus 15 minutes. WidgetKit asks again when the app reloads.
enum Timelines {
    static let store = HandoffStore(appGroup: HandoffStore.bundleAppGroup)
    static let needs = WidgetNeedsStore(appGroup: HandoffStore.bundleAppGroup)

    static func theme(_ choice: ThemeChoice, _ h: Handoff?) -> Theme {
        switch choice {
        case .bar: h?.decodedTheme ?? ThemeStore.native
        default: ThemeStore().theme(choice.rawValue)
        }
    }

    static func entries(kind: WidgetModel.Kind, right: WidgetModel.Right, theme choice: ThemeChoice,
                        family: WidgetFamily, key: String) -> [Entry] {
        let now = Date()
        let h = store.read()
        // The language the user chose in the app, for every word drawn.
        L10n.prefer(h?.decodedSettings.language.localization)
        var node: String?
        var service: String?
        if case .server(let n, _) = kind { node = n }
        if case .service(let id) = kind { service = id }
        needs.record(key, .init(lists: family == .systemLarge || family == .systemExtraLarge, node: node, service: service, at: now))
        let theme = theme(choice, h)
        return WidgetSchedule.entries(h, at: now, server: node, service: service).map { e in
            Entry(date: e.date, model: WidgetModel(kind: kind, right: right, panel: e.panel, isCurrent: e.isCurrent), theme: theme)
        }
    }

    /// A Time zones widget's: one a minute for an hour, each with its
    /// clocks.
    static func zones(theme choice: ThemeChoice, family: WidgetFamily, key: String) -> [Entry] {
        let now = Date()
        let h = store.read()
        L10n.prefer(h?.decodedSettings.language.localization)
        needs.record(key, .init(lists: false, node: nil, zones: true, at: now))
        let theme = theme(choice, h)
        return WidgetSchedule.zonesEntries(h, at: now).map { e in
            Entry(date: e.date, model: WidgetModel(kind: .zones, panel: e.panel, isCurrent: e.isCurrent), theme: theme)
        }
    }
}

struct StatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Timelines.entries(kind: .status, right: .automatic, theme: .bar, family: context.family, key: "placeholder")[0]
    }

    func snapshot(for configuration: StatusWidgetIntent, in context: Context) async -> Entry {
        timeline(configuration, context)[0]
    }

    func timeline(for configuration: StatusWidgetIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: timeline(configuration, context), policy: .never)
    }

    func timeline(_ c: StatusWidgetIntent, _ context: Context) -> [Entry] {
        Timelines.entries(kind: .status, right: c.right.model, theme: c.theme, family: context.family,
                          key: "status-\(context.family)-\(c.right.rawValue)")
    }
}

struct ServerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Timelines.entries(kind: .server(node: "", isMac: false), right: .automatic, theme: .bar, family: context.family,
                          key: "placeholder")[0]
    }

    func snapshot(for configuration: ServerWidgetIntent, in context: Context) async -> Entry {
        timeline(configuration, context)[0]
    }

    func timeline(for configuration: ServerWidgetIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: timeline(configuration, context), policy: .never)
    }

    func timeline(_ c: ServerWidgetIntent, _ context: Context) -> [Entry] {
        let node = c.node ?? NodeQuery.known().first
        return Timelines.entries(kind: .server(node: node?.id ?? "", isMac: node?.isMac ?? false), right: .automatic,
                                 theme: c.theme, family: context.family, key: "server-\(context.family)-\(node?.id ?? "")")
    }
}

struct ServiceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Timelines.entries(kind: .service(id: ""), right: .automatic, theme: .bar, family: context.family, key: "placeholder")[0]
    }

    func snapshot(for configuration: ServiceWidgetIntent, in context: Context) async -> Entry {
        timeline(configuration, context)[0]
    }

    func timeline(for configuration: ServiceWidgetIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: timeline(configuration, context), policy: .never)
    }

    func timeline(_ c: ServiceWidgetIntent, _ context: Context) -> [Entry] {
        let service = c.service ?? ServiceQuery.known().first
        return Timelines.entries(kind: .service(id: service?.id ?? ""), right: .automatic, theme: c.theme, family: context.family,
                                 key: "service-\(context.family)-\(service?.id ?? "")")
    }
}

struct ZonesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Timelines.zones(theme: .bar, family: context.family, key: "placeholder-zones")[0]
    }

    func snapshot(for configuration: ZonesWidgetIntent, in context: Context) async -> Entry {
        timeline(configuration, context)[0]
    }

    func timeline(for configuration: ZonesWidgetIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: timeline(configuration, context), policy: .never)
    }

    func timeline(_ c: ZonesWidgetIntent, _ context: Context) -> [Entry] {
        Timelines.zones(theme: c.theme, family: context.family, key: "zones-\(context.family)")
    }
}

// MARK: views

struct WidgetView: View {
    var entry: Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var size: WidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge: .large
        default: .extraLarge
        }
    }

    var body: some View {
        let rendering: RenderContext.WidgetRendering = mode == .vibrant ? .vibrant : mode == .accented ? .accented : .fullColor
        var ctx = RenderContext(theme: entry.theme, colorScheme: scheme, backdrop: .flat, reduceTransparency: reduceTransparency,
                                increaseContrast: contrast == .increased, widgetRendering: rendering)
        let _ = ctx.liveDates = true
        let r = Renderers.renderer(for: entry.theme)
        let model = entry.model, size = size, context = ctx
        // WidgetKit's sizes vary with the display, so lay out in the one given.
        GeometryReader { g in
            r.widget(model, size: size, bounds: g.size, context: context)
        }
        .containerBackground(for: .widget) { r.widgetBackground(context: context) }
        .environment(\.locale, L10n.locale)
        .widgetURL(WidgetLinks.panel)
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "status", intent: StatusWidgetIntent.self, provider: StatusProvider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Status")
        .description("What the collector concludes right now.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct ServerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "server", intent: ServerWidgetIntent.self, provider: ServerProvider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Server")
        .description("One server's card, as in the Servers tab.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct ServiceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "service", intent: ServiceWidgetIntent.self, provider: ServiceProvider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Service")
        .description("One service's card, as in the Services tab.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct ZonesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "zones", intent: ZonesWidgetIntent.self, provider: ZonesProvider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Time Zones")
        .description("The time where your servers are, and each one’s health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
