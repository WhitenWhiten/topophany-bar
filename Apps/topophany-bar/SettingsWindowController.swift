import AppKit
import SwiftUI
import TopophanySections

/// Settings: General, Appearance, Sections and This Mac, as toolbar tabs.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        func tab<V: View>(_ title: String, _ symbol: String, _ view: V) -> NSTabViewItem {
            let host = NSHostingController(rootView: view.environment(model))
            host.sizingOptions = [.preferredContentSize]
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
