import AppKit
import SwiftUI
import TopophanySections
import TopophanyThemes

/// The panel under the status item: a borderless NSPanel hosting the
/// theme's renderer.
@MainActor
final class PanelController: NSObject {
    struct Actions {
        var openTerminal: () -> Void
        var openSettings: () -> Void
        var quit: () -> Void
        var openAttention: (AttentionSection.Item?) -> Void
    }

    var actions: Actions?
    /// Called as the panel opens and closes, for the menu bar item.
    var onOpenChange: ((Bool) -> Void)?
    private let model: AppModel
    private var panel: KeyPanel?
    private var hosting: NSHostingView<PanelRoot>?
    private var monitors: [Any] = []
    private weak var anchor: NSStatusBarButton?

    init(model: AppModel) {
        self.model = model
    }

    var isOpen: Bool { panel?.isVisible == true }

    var window: NSWindow? { panel }

    /// Presses a key as the keyboard would: `up`, `down` or `return`.
    func press(_ name: String) {
        switch name {
        case "up": move(-1)
        case "down": move(1)
        case "return": activate()
        default: break
        }
    }

    func toggle(from button: NSStatusBarButton) {
        if isOpen { close() } else { open(from: button) }
    }

    func open(from button: NSStatusBarButton) {
        anchor = button
        let p = panel ?? makePanel()
        panel = p
        model.focus = nil
        model.refresh()
        layout()
        onOpenChange?(true)
        p.orderFrontRegardless()
        p.makeKey()
        installMonitors()
    }

    func close() {
        guard let p = panel, p.isVisible else { return }
        p.orderOut(nil)
        onOpenChange?(false)
        model.focus = nil
        removeMonitors()
    }

    func update() {
        guard isOpen else { return }
        layout()
    }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 344, height: 400),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.animationBehavior = .utilityWindow
        p.isReleasedWhenClosed = false
        let root = PanelRoot(model: model, actions: panelActions, maxHeight: { [weak self] in self?.maxHeight ?? 800 })
        let h = NSHostingView(rootView: root)
        h.sizingOptions = [.intrinsicContentSize]
        p.contentView = h
        hosting = h
        return p
    }

    private var panelActions: PanelActions {
        PanelActions(openTerminal: { [weak self] in self?.actions?.openTerminal() },
                     openSettings: { [weak self] in self?.actions?.openSettings() },
                     quit: { [weak self] in self?.actions?.quit() },
                     openAttention: { [weak self] item in self?.actions?.openAttention(item) },
                     focus: { [weak self] id in self?.model.focus = id })
    }

    private var screen: NSScreen? { anchor?.window?.screen ?? NSScreen.main }

    private var maxHeight: Double {
        guard let s = screen else { return 800 }
        let menuBar = s.frame.maxY - s.visibleFrame.maxY
        return s.frame.height - menuBar - 12
    }

    private func layout() {
        guard let p = panel, let h = hosting else { return }
        h.layoutSubtreeIfNeeded()
        let size = h.fittingSize
        guard let s = screen else { return }
        // The glass alone gives the window a square shadow, edged in black
        // past the corners; masked, the shadow follows the panel's shape.
        h.wantsLayer = true
        h.layer?.cornerRadius = Renderers.renderer(for: model.theme).panelCornerRadius
        h.layer?.cornerCurve = .continuous
        h.layer?.masksToBounds = true
        let bf = anchor?.window?.frame ?? NSRect(x: s.frame.midX, y: s.visibleFrame.maxY, width: 0, height: 0)
        var x = bf.midX - size.width / 2
        x = min(max(x, s.visibleFrame.minX + 8), s.visibleFrame.maxX - size.width - 8)
        let top = min(bf.minY, s.visibleFrame.maxY) - 5
        p.setFrame(NSRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height), display: true)
    }

    // MARK: keyboard and clicks outside

    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] e in
            nonisolated(unsafe) let event = e
            let handled = MainActor.assumeIsolated { self?.key(event) == true }
            return handled ? nil : e
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// ↑↓ move, ↵ opens, Esc closes, ⌘O ⌘, ⌘Q.
    private func key(_ e: NSEvent) -> Bool {
        guard isOpen, e.window === panel else { return false }
        let cmd = e.modifierFlags.contains(.command)
        switch (e.keyCode, cmd, e.charactersIgnoringModifiers ?? "") {
        case (53, _, _): close(); return true
        case (126, false, _): move(-1); return true
        case (125, false, _): move(1); return true
        case (36, false, _), (76, false, _): activate(); return true
        case (_, true, "o"): actions?.openTerminal(); return true
        case (_, true, ","): actions?.openSettings(); return true
        case (_, true, "q"): actions?.quit(); return true
        default: return false
        }
    }

    private func move(_ d: Int) {
        let order = Renderers.focusOrder(model.panel)
        guard !order.isEmpty else { return }
        if let f = model.focus, let i = order.firstIndex(of: f) {
            model.focus = order[(i + d + order.count) % order.count]
        } else {
            model.focus = d > 0 ? order.first : order.last
        }
        if let f = model.focus { announce(f) }
    }

    private func activate() {
        guard let f = model.focus else { actions?.openTerminal(); return }
        if f == "attention:more" { actions?.openAttention(nil); return }
        if f.hasPrefix("attention:"), let item = model.panel.attention?.items.first(where: { "attention:" + $0.id == f }) {
            actions?.openAttention(item)
            return
        }
        actions?.openTerminal()
    }

    /// VoiceOver reads the row the keyboard moved to.
    private func announce(_ id: String) {
        var text = ""
        if id.hasPrefix("attention:"), let a = model.panel.attention?.items.first(where: { "attention:" + $0.id == id }) {
            text = "\(a.title), \(a.pill.text)"
        } else if id == "attention:more", let a = model.panel.attention {
            text = String(localized: "\(a.more) more in Topophany")
        } else if id.hasPrefix("seen:"), let o = model.panel.seen?.problems?.first(where: { "seen:" + $0.id == id }) {
            text = "\(o.name), \(o.note)"
        } else if id.hasPrefix("app:"), let a = model.panel.applications?.rows.first(where: { "app:" + $0.id == id }) {
            text = "\(a.name), \(a.note)"
        } else if id.hasPrefix("server:") {
            let cards = model.panel.servers + (model.panel.mac.flatMap { if case .server(let c, _) = $0 { [c] } else { nil } } ?? [])
            if let c = cards.first(where: { "server:" + $0.id == id }) { text = "\(c.name), \(c.pill.text)" }
        }
        guard !text.isEmpty, let p = panel else { return }
        NSAccessibility.post(element: p, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The panel's SwiftUI root: the theme's renderer, told what the system
/// asks for.
struct PanelRoot: View {
    var model: AppModel
    var actions: PanelActions
    var maxHeight: () -> Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let s = model.settings.appearance
        let scheme: ColorScheme = s.panel == .light ? .light : s.panel == .dark ? .dark : systemScheme
        let ctx = RenderContext(theme: model.theme, colorScheme: scheme, backdrop: .live, textSize: s.textSize,
                                focus: model.focus, reduceTransparency: reduceTransparency,
                                increaseContrast: contrast == .increased, maxHeight: maxHeight())
        Renderers.renderer(for: model.theme).panel(model.panel, context: ctx)
            .environment(\.panelActions, actions)
            .preferredColorScheme(model.theme.renderer == .cells ? .dark : (s.panel == .system ? nil : scheme))
    }
}
