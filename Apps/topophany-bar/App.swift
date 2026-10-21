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
    private let panelShortcut = PanelShortcutController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.widgets = WidgetBridge(store: HandoffStore(appGroup: HandoffStore.bundleAppGroup))
        let panel = PanelController(model: model)
        let item = StatusItemController(model: model) { [weak panel] button in panel?.toggle(from: button) }
        panel.actions = PanelController.Actions(
            openTerminal: { [weak self] in self?.openTUI(focus: nil) },
            openSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) },
            openAttention: { [weak self] item in self?.openTUI(focus: item) },
            toggleQuiet: { [weak self] in self?.model.toggleQuiet() })
        panel.onOpenChange = { [weak item] open in item?.pressed = open }
        item.contextMenu = { [weak self] in self?.itemMenu() }
        self.panel = panel
        statusItem = item
        panelShortcut.onPress = { [weak panel, weak item] in
            if let button = item?.button { panel?.toggle(from: button) }
        }
        panelShortcut.configure(model.settings.panelShortcut)
        model.onChange = { [weak item, weak panel] in
            item?.update()
            panel?.update()
        }
        model.onSettingsChange = { [weak self] old, new in
            if old.panelShortcut != new.panelShortcut { self?.panelShortcut.configure(new.panelShortcut) }
            if old.openAtLogin != new.openAtLogin { self?.applyLoginItem() }
            if old.language != new.language {
                self?.settings?.relabel()
                if NSApp.mainMenu != nil, let self { NSApp.mainMenu = MainMenu.make(target: self) }
            }
        }
        // Once a window has gone: another may open in its place, as About
        // does when it's shown again.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.windowClosed() }
        }
        model.start()
        applyLoginItem()
        WidgetNeedsWatcher.start(model: model)
        #if DEBUG
        DebugSnapshots.run(delegate: self)
        DebugDriver.start(delegate: self)
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
        panelShortcut.stop()
        // stdin closes and topo exits; it writes its last frame first.
        model.stopNow()
    }

    /// The menu bar item's right-click menu: About, quiet its alert, open
    /// the TUI or Settings, quit.
    func itemMenu() -> NSMenu {
        panel?.close()
        let menu = NSMenu()
        let about = NSMenuItem(title: tr("About Topophany"), action: #selector(showAboutFromMenu), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let alert = model.panel.alert
        let quiet = NSMenuItem(title: tr("Quiet Until It Gets Worse"), action: #selector(toggleQuiet), keyEquivalent: "")
        quiet.target = self
        quiet.state = alert == .quiet ? .on : .off
        quiet.isEnabled = alert != .unavailable
        quiet.toolTip = tr("The menu bar item keeps its badge’s shape, in its own color, until this gets worse.")
        menu.addItem(quiet)
        menu.addItem(.separator())
        let open = NSMenuItem(title: tr("Open in Terminal"), action: #selector(openTUIFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: tr("Settings…"), action: #selector(showSettingsFromMenu), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: tr("Quit Topophany"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        // The menu checks items by their target; quitting needs none.
        menu.autoenablesItems = false
        return menu
    }

    @objc private func toggleQuiet() { model.toggleQuiet() }
    @objc private func openTUIFromMenu() { openTUI(focus: nil) }
    @objc func showSettingsFromMenu() { showSettings() }
    @objc func showAboutFromMenu() { showAbout() }

    func showSettings() {
        panel?.close()
        if settings == nil { settings = SettingsWindowController(model: model, shortcut: panelShortcut) }
        comeForward()
        settings?.show()
    }

    /// The standard About panel, with the version of the `topo` running.
    func showAbout() {
        panel?.close()
        comeForward()
        var topo: String?
        if case .running(let r) = model.engineStatus { topo = r.version }
        About.show(topo: topo)
        NSApp.activate()
    }

    /// An accessory app comes forward only while one of its windows is
    /// open: with a Dock icon, and a menu bar for the keys a window
    /// answers to.
    private func comeForward() {
        NSApp.mainMenu = MainMenu.make(target: self)
        NSApp.setActivationPolicy(.regular)
    }

    /// Back to the menu bar alone once the last window has closed. The
    /// panel and the item's own window have no title bar.
    private func windowClosed() {
        let open = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        guard !open, NSApp.activationPolicy() == .regular else { return }
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = nil
    }

    func openTUI(focus: AttentionSection.Item?) {
        panel?.close()
        TerminalLauncher.open(model: model, focus: focus)
    }

    #if DEBUG
    var statusItemImage: NSImage? { statusItem?.frame }
    var statusButton: NSStatusBarButton? { statusItem?.button }
    var panelWindow: NSWindow? { panel?.window }
    var settingsWindow: NSWindow? { settings?.window }
    func openPanelForSnapshot() { if let b = statusItem?.button { panel?.open(from: b) } }
    func closePanel() { panel?.close() }
    func panelKey(_ name: String) { panel?.press(name) }
    /// A scroll in the panel, as the app's own monitor takes it: true when
    /// the map took it.
    func panelScroll(_ e: NSEvent) -> Bool { panel?.scroll(e) ?? false }
    func selectSettingsTab(_ i: Int) { settings?.select(i) }
    #endif

    func applyLoginItem() {
        // macOS keeps one login item per bundle ID, the installed copy's: a
        // debug build with a fixture, snapshots or a test settings file
        // leaves it alone.
        #if DEBUG
        if DebugSnapshots.directory != nil || model.fixture != nil
            || UserDefaults.standard.string(forKey: "settings") != nil { return }
        #endif
        let service = SMAppService.mainApp
        if model.settings.openAtLogin {
            if service.status != .enabled { try? service.register() }
        } else if service.status == .enabled {
            try? service.unregister()
        }
    }
}
