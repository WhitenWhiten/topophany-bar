import AppKit
import SwiftUI
import TopophanySections

/// Settings: General, Appearance, Sections and This Mac, as toolbar tabs.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let model: AppModel
    private let tabs = SettingsTabs()

    init(model: AppModel, shortcut: PanelShortcutController) {
        self.model = model
        let tabs = self.tabs
        tabs.tabStyle = .toolbar
        func tab<V: View>(_ symbol: String, _ view: V) -> NSTabViewItem {
            let index = tabs.tabViewItems.count
            let host = NSHostingController(rootView: Localized(content: view).environment(model).environment(shortcut)
                .environment(\.fitSettings, SettingsFitter(tab: index, tabs: tabs)))
            // The window follows the forms' heights itself (SettingsTabs).
            host.sizingOptions = []
            let item = NSTabViewItem(viewController: host)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return item
        }
        tabs.addTabViewItem(tab("gearshape", GeneralSettings()))
        tabs.addTabViewItem(tab("circle.lefthalf.filled", AppearanceSettings()))
        tabs.addTabViewItem(tab("list.bullet", SectionsSettings()))
        tabs.addTabViewItem(tab("apple.logo", MacSettings()))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("topophany-bar.settings")
        super.init(window: window)
        relabel()
        // Back from the terminal or Finder: look again for topo and profiles.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak model] _ in
            MainActor.assumeIsolated {
                model?.locate()
                shortcut.configure(model?.settings.panelShortcut)
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak model] _ in
            MainActor.assumeIsolated { model?.setSettingsVisible(false) }
        }
    }

    /// Names the tabs, and the window after the one shown, in the language
    /// the user chose.
    func relabel() {
        let titles = [tr("General"), tr("Appearance"), tr("Sections"), tr("This Mac")]
        for (item, title) in zip(tabs.tabViewItems, titles) {
            item.label = title
            item.viewController?.title = title
            item.image?.accessibilityDescription = title
        }
        let selected = tabs.selectedTabViewItemIndex
        if titles.indices.contains(selected) { window?.title = titles[selected] }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show() {
        model.setSettingsVisible(true)
        // Becoming key performs the scan; repeated show calls on the same
        // key window need no second scan.
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func select(_ index: Int) {
        (window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = index
    }
}

/// Toolbar tabs whose window is the size of the selected form, top edge
/// fixed. It eases to a new size when a tab is chosen or its form grows or
/// shrinks, rather than waiting on `preferredContentSize`. A new size while
/// it moves carries on from where the window is.
@MainActor
final class SettingsTabs: NSTabViewController {
    private var sizes: [Int: CGSize] = [:]
    private var move: (from: NSRect, to: NSRect, start: CFTimeInterval)?
    private var link: CADisplayLink?
    private let duration = 0.24

    func fit(_ size: CGSize, tab: Int) {
        guard size.width > 0, size.height > 0, sizes[tab] != size else { return }
        sizes[tab] = size
        if tab == selectedTabViewItemIndex { resize(to: size) }
    }

    // Sizes reported before the window existed.
    override func viewWillAppear() {
        super.viewWillAppear()
        if let size = sizes[selectedTabViewItemIndex] { resize(to: size) }
    }

    override func tabView(_ tabView: NSTabView, willSelect item: NSTabViewItem?) {
        super.tabView(tabView, willSelect: item)
        if let item, let size = sizes[tabView.indexOfTabViewItem(item)] { resize(to: size) }
    }

    private func resize(to size: CGSize) {
        guard let window = view.window else { return }
        let now = window.frame
        // The title bar and toolbar, which the content runs beneath.
        let chrome = now.height - window.contentLayoutRect.height
        let target = CGSize(width: size.width.rounded(), height: (size.height + chrome).rounded())
        var to = move?.to ?? now
        guard abs(target.height - to.height) >= 0.5 || abs(target.width - to.width) >= 0.5 else { return }
        to.origin.y = now.maxY - target.height
        to.origin.x = (now.midX - target.width / 2).rounded()
        to.size = target
        guard window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stop()
            window.setFrame(to, display: true)
            return
        }
        move = (now, to, CACurrentMediaTime())
        if link == nil {
            let link = window.displayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let window = view.window, let m = move else { return stop() }
        let t = min(1, (CACurrentMediaTime() - m.start) / duration)
        let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        func mix(_ a: Double, _ b: Double) -> Double { (a + (b - a) * e).rounded() }
        let height = mix(m.from.height, m.to.height), width = mix(m.from.width, m.to.width)
        window.setFrame(NSRect(x: mix(m.from.minX, m.to.minX), y: m.to.maxY - height, width: width, height: height),
                        display: true)
        if t >= 1 { stop() }
    }

    private func stop() {
        link?.invalidate()
        link = nil
        move = nil
    }
}
