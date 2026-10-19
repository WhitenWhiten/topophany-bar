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
    }
}

// MARK: configuration

enum ThemeChoice: String, AppEnum {
    case bar, native, terminal

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Theme"
    static let caseDisplayRepresentations: [ThemeChoice: DisplayRepresentation] = [
        .bar: "Same as the Menu Bar",
        .native: "Native",
        .terminal: "Terminal",
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
        case .native: ThemeStore.native
        case .terminal: ThemeStore.terminal
        }
    }

    static func entries(kind: WidgetModel.Kind, right: WidgetModel.Right, theme choice: ThemeChoice,
                        family: WidgetFamily, key: String) -> [Entry] {
        let now = Date()
        let h = store.read()
        var node: String?
        if case .server(let n, _) = kind { node = n }
        needs.record(key, .init(lists: family == .systemLarge || family == .systemExtraLarge, node: node, at: now))
        let theme = theme(choice, h)
        return WidgetSchedule.entries(h, at: now, server: node).map { e in
            Entry(date: e.date, model: WidgetModel(kind: kind, right: right, panel: e.panel, isCurrent: e.isCurrent), theme: theme)
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
