import Foundation
import TopophanyWidgets

/// Reads what the desktop's widgets draw, and widens the app's request to
/// match, every 30 seconds.
@MainActor
enum WidgetNeedsWatcher {
    private static var timer: Timer?

    static func start(model: AppModel) {
        let store = WidgetNeedsStore(appGroup: HandoffStore.bundleAppGroup)
        guard store.directory != nil else { return }
        check(model, store)
        let t = Timer(timeInterval: 30, repeats: true) { [weak model] _ in
            MainActor.assumeIsolated { if let model { check(model, store) } }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private static func check(_ model: AppModel, _ store: WidgetNeedsStore) {
        let needs = store.needs()
        model.widgets?.needs = needs
        model.widgets?.zones = store.zones()
        model.setWidgetNeeds(needs)
    }
}
