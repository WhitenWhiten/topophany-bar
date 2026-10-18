import AppKit
import ServiceManagement
import TopophanySections
import TopophanyWidgets

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    let model = AppModel()
    private var statusItem: StatusItemController?
    private var panel: PanelController?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.widgets = WidgetBridge(store: HandoffStore(appGroup: HandoffStore.bundleAppGroup))
        let panel = PanelController(model: model)
        let item = StatusItemController(model: model) { [weak panel] button in panel?.toggle(from: button) }
        panel.actions = PanelController.Actions(
            openTerminal: { [weak self] in self?.openTUI(focus: nil) },
            openSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) },
            openAttention: { [weak self] item in self?.openTUI(focus: item) })
        self.panel = panel
        statusItem = item
        model.onChange = { [weak item, weak panel] in
            item?.update()
            panel?.update()
        }
        model.start()
        applyLoginItem()
        WidgetNeedsWatcher.start(model: model)
        #if DEBUG
        DebugSnapshots.run(delegate: self)
        #endif
    }

    /// Widgets' links: `topophany-bar://panel` opens the panel, and
    /// `topophany-bar://attention?kind=…&id=…` the TUI on that entry's page.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "topophany-bar" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            switch url.host() {
            case "attention":
                let id = value("id") ?? ""
                let item = model.panel.attention?.items.first { $0.id == id }
                    ?? AttentionSection.Item(id: id, kind: value("kind") ?? "", route: [], mark: .unknown,
                                             pill: .health(.unknown), observer: "", observerName: "", since: nil)
                openTUI(focus: item)
            default:
                if let b = statusItem?.button, panel?.isOpen != true { panel?.open(from: b) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // stdin closes and topo exits; it writes its last frame first.
        model.stopNow()
    }

    func showSettings() {
        panel?.close()
        if settings == nil { settings = SettingsWindowController(model: model) }
        settings?.show()
    }

    func openTUI(focus: AttentionSection.Item?) {
        panel?.close()
        TerminalLauncher.open(model: model, focus: focus)
    }

    #if DEBUG
    var statusItemImage: NSImage? { statusItem?.button?.image }
    var panelWindow: NSWindow? { panel?.window }
    var settingsWindow: NSWindow? { settings?.window }
    func openPanelForSnapshot() { if let b = statusItem?.button { panel?.open(from: b) } }
    func panelKey(_ name: String) { panel?.press(name) }
    func selectSettingsTab(_ i: Int) { settings?.select(i) }
    #endif

    func applyLoginItem() {
        // A debug build run from the build folder doesn't register itself.
        #if DEBUG
        if DebugSnapshots.directory != nil || model.fixture != nil { return }
        #endif
        let service = SMAppService.mainApp
        if model.settings.openAtLogin {
            if service.status != .enabled { try? service.register() }
        } else if service.status == .enabled {
            try? service.unregister()
        }
    }
}
