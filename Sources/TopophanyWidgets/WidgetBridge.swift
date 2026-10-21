import Foundation
import TopophanyKit
import TopophanySections
import TopophanyThemes
import WidgetKit

/// The app's side of the hand-off: it is the only reader of `topo`, so it
/// keeps the latest frame in the App Group and tells WidgetKit when to
/// reload.
@MainActor
public final class WidgetBridge {
    public let store: HandoffStore
    /// Nodes and lists the widgets on the desktop draw beyond the panel.
    public var needs = TemplateCompiler.WidgetNeeds.none
    /// A Time zones widget is on the desktop.
    public var zones = false
    private var policy = WidgetReloadPolicy()
    private struct Look: Equatable {
        var theme: Theme
        var language: TopophanyKit.Settings.Language
        var sections: Sections
        var needs: TemplateCompiler.WidgetNeeds
        var zones: Bool
        var extra: String
    }
    private var lastLook: Look?
    private let reload: @MainActor () -> Void

    public init(store: HandoffStore, reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store
        self.reload = reload
    }

    /// Called every second with what the panel shows.
    public func tick(panel: PanelModel? = nil, status: StatusSection? = nil, reading: Reading, policy reader: ReaderPolicy, theme: Theme, settings: TopophanyKit.Settings,
                     at now: Date = Date()) {
        guard store.isAvailable else { return }
        // A change of theme, language or what widgets show reloads too, and
        // so does a Server or Service widget's card changing health, or with a Time
        // zones widget, any listed server's, or with a Map widget, any place's
        // or line's on the map.
        // A hidden panel needs no layout models for clocks, local readings,
        // Fleet or the map. Reuse the app's evaluation and any visible cards.
        var panel = panel ?? signaturePanel(reading, settings: settings)
        if let status { panel.status = status }
        if needs.lists {
            if panel.seen == nil { panel.sections.append(.seen(SectionBuilder.seen(reading))) }
            if panel.attention == nil, let a = SectionBuilder.attention(reading, limit: max(3, settings.sections.attentionLimit)) {
                panel.sections.append(.attention(a))
            }
            if panel.applications == nil, let a = SectionBuilder.applications(reading, only: settings.sections.applicationsOnly) {
                panel.sections.append(.applications(a))
            }
        }
        let nodes = needs.nodes.filter { id in !panel.servers.contains { $0.id == id } }
        let services = needs.services.filter { id in !panel.services.contains { $0.id == id } }
        var extra = SectionBuilder.servers(reading, nodes: nodes)
            .map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")
        extra += ";" + SectionBuilder.services(reading, ids: services)
            .map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")
        if zones, let fleet = SectionBuilder.fleet(reading, pinned: settings.sections.serverNodes) {
            extra += ";" + fleet.groups.flatMap(\.nodes).map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")
        }
        // A Map widget's places and lines, as each is marked.
        if needs.map, let map = SectionBuilder.map(reading, sections: settings.sections, observer: settings.topo.observer) {
            extra += ";" + map.nodes.map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")
                + ";" + map.edges.map { "\($0.line.rank)" }.joined(separator: ",")
        }
        let look = Look(theme: theme, language: settings.language, sections: settings.sections, needs: needs, zones: zones, extra: extra)
        let changedLook = look != lastLook
        guard policy.shouldReload(panel, at: now) || changedLook else { return }
        lastLook = look
        var running = false
        if case .open = reader.source { running = true }
        try? store.write(Handoff(policy: reader, theme: theme, settings: settings, engineRunning: running, at: now))
        reload()
    }

    private func signaturePanel(_ reading: Reading, settings: TopophanyKit.Settings) -> PanelModel {
        var s = settings
        s.sections.order.removeAll { [.zones, .fleet, .map].contains($0) }
        if s.sections.mac.mode == .local { s.sections.mac.mode = .off }
        s.sections.seen = s.sections.seen || needs.lists
        s.sections.attention = s.sections.attention || needs.lists
        s.sections.applications = s.sections.applications || needs.lists
        return SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: s))
    }
}
