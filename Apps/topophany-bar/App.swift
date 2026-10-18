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
