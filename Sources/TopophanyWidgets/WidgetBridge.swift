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
    private var policy = WidgetReloadPolicy()
    private var lastLook: String?
    private let reload: @MainActor () -> Void

    public init(store: HandoffStore, reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store
        self.reload = reload
    }

    /// Called every second with what the panel shows.
    public func tick(panel: PanelModel, policy reader: ReaderPolicy, theme: Theme, settings: TopophanyKit.Settings,
                     at now: Date = Date()) {
        guard store.isAvailable else { return }
        // A change of theme, language or what widgets show reloads too, and
        // so does a Server widget's card changing health.
        let extra = SectionBuilder.servers(reader.evaluate(at: now), nodes: needs.nodes)
            .map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")
        let look = theme.id + settings.language.rawValue + String(describing: settings.sections) + String(describing: needs) + extra
        let changedLook = look != lastLook
        guard policy.shouldReload(panel, at: now) || changedLook else { return }
        lastLook = look
        var running = false
        if case .open = reader.source { running = true }
        try? store.write(Handoff(policy: reader, theme: theme, settings: settings, engineRunning: running, at: now))
        reload()
    }
}
