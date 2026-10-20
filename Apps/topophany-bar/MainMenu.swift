import AppKit

/// The menu bar the app has while one of its windows is open (Settings),
/// in the language the user chose: the keys a window answers to,
/// ⌘W, ⌘Q, and ⌘C and ⌘V in its fields. The panel answers ⌘O, ⌘, and ⌘Q
/// itself.
@MainActor
enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let bar = NSMenu()
        bar.addItem(submenu(tr("Topophany"), [
            item(tr("Settings…"), #selector(AppDelegate.showSettingsFromMenu), ",", target: target),
            .separator(),
            item(tr("Hide Topophany"), #selector(NSApplication.hide(_:)), "h"),
            item(tr("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item(tr("Show All"), #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item(tr("Quit Topophany"), #selector(NSApplication.terminate(_:)), "q"),
        ]))
        bar.addItem(submenu(tr("File"), [
            item(tr("Close"), #selector(NSWindow.performClose(_:)), "w"),
        ]))
        bar.addItem(submenu(tr("Edit"), [
            item(tr("Undo"), Selector(("undo:")), "z"),
            item(tr("Redo"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(tr("Cut"), #selector(NSText.cut(_:)), "x"),
            item(tr("Copy"), #selector(NSText.copy(_:)), "c"),
            item(tr("Paste"), #selector(NSText.paste(_:)), "v"),
            item(tr("Select All"), #selector(NSText.selectAll(_:)), "a"),
        ]))
        return bar
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// An item for `target`, or else for the first responder that answers.
    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
