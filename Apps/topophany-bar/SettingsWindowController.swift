import AppKit
import SwiftUI
import TopophanySections

/// Settings: General, Appearance, Sections and This Mac, as toolbar tabs.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        func tab<V: View>(_ title: String, _ symbol: String, _ view: V) -> NSTabViewItem {
            let index = tabs.tabViewItems.count
            let host = NSHostingController(rootView: view.environment(model)
                .environment(\.fitSettings, SettingsFitter(tab: index, tabs: tabs)))
            // The window follows the forms' heights itself (SettingsTabs).
            host.sizingOptions = []
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }
        tabs.addTabViewItem(tab(String(localized: "General"), "gearshape", GeneralSettings()))
        tabs.addTabViewItem(tab(String(localized: "Appearance"), "circle.lefthalf.filled", AppearanceSettings()))
        tabs.addTabViewItem(tab(String(localized: "Sections"), "list.bullet", SectionsSettings()))
        tabs.addTabViewItem(tab(String(localized: "This Mac"), "laptopcomputer", MacSettings()))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("topophany-bar.settings")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show() {
        model.locate()
        // An accessory app comes forward only while a window is open.
        NSApp.setActivationPolicy(.regular)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func select(_ index: Int) {
        (window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = index
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
