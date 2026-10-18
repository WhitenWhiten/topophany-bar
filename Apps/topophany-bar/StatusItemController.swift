import AppKit
import SwiftUI
import TopophanySections
import TopophanyThemes

/// The menu bar item: the verdict, drawn by the theme's renderer, as an
/// image the system tints when status colors are off.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let onClick: (NSStatusBarButton) -> Void
    private var drawn: (StatusItemModel, String, Bool)?
    private var appearanceWatch: NSKeyValueObservation?

    init(model: AppModel, onClick: @escaping (NSStatusBarButton) -> Void) {
        self.model = model
        self.onClick = onClick
        super.init()
        if let b = item.button {
            b.target = self
            b.action = #selector(clicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.imagePosition = .imageOnly
            appearanceWatch = b.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update(force: true) }
            }
        }
        item.autosaveName = "topophany-bar"
        update(force: true)
    }

    @objc private func clicked() {
        if let b = item.button { onClick(b) }
    }

    var button: NSStatusBarButton? { item.button }

    func update(force: Bool = false) {
        guard let b = item.button else { return }
        let m = model.statusItem
        let theme = model.theme
        let dark = b.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if !force, let d = drawn, d.0 == m, d.1 == theme.id, d.2 == dark { return }
        drawn = (m, theme.id, dark)
        let template = theme.renderer == .cards && !m.statusColors
        let ctx = StatusItemContext(theme: theme, menuBarIsDark: dark, template: template)
        let view = Renderers.renderer(for: theme).statusItem(m, context: ctx)
        let r = ImageRenderer(content: view)
        r.scale = b.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let cg = r.cgImage else { return }
        let size = NSSize(width: CGFloat(cg.width) / r.scale, height: CGFloat(cg.height) / r.scale)
        let image = NSImage(cgImage: cg, size: size)
        image.isTemplate = template
        b.image = image
        b.setAccessibilityLabel(m.accessibilityLabel)
        b.toolTip = m.accessibilityLabel
    }
}
