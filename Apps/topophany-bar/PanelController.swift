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
        var toggleQuiet: () -> Void
    }

    var actions: Actions?
    /// Called as the panel opens and closes, for the menu bar item.
    var onOpenChange: ((Bool) -> Void)?
    private let model: AppModel
    private var panel: KeyPanel?
    private var hosting: NSHostingView<PanelRoot>?
    private var monitors: [Any] = []
    private weak var anchor: NSStatusBarButton?
    /// Open, or opening: a closing panel fades out still visible.
    private(set) var isOpen = false
    /// Counts each open and close, so a fade that finishes late does nothing.
    private var turn = 0
    private let height = PanelHeight()
    /// While the foot is dragged: where the pointer and the panel's height
    /// were when it began, in points down from the top of the screens, and
    /// whether it has moved since.
    private var footDrag: (pointer: Double, height: Double, moved: Bool)?

    /// The band at the panel's foot that drags its height.
    static let footBand = 6.0

    init(model: AppModel) {
        self.model = model
    }

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

    /// The panel fades in as it settles a few points down from the menu
    /// bar; under Reduce Motion it only fades.
    func open(from button: NSStatusBarButton) {
        anchor = button
        let p = panel ?? makePanel()
        panel = p
        isOpen = true
        turn += 1
        model.focus = nil
        model.refresh()
        // Only a height the user chose can be too short.
        height.shortest = model.settings.appearance.panelHeight == nil ? 0 : measureShortest()
        layout()
        onOpenChange?(true)
        let end = p.frame.origin
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !p.isVisible {
            p.alphaValue = 0
            if !still { p.setFrameOrigin(NSPoint(x: end.x, y: end.y + 4)) }
        }
        p.orderFrontRegardless()
        p.makeKey()
        installMonitors()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = still ? 0.12 : 0.2
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            p.animator().alphaValue = 1
            if !still { p.animator().setFrame(NSRect(origin: end, size: p.frame.size), display: true) }
        }
    }

    /// The panel fades out, quicker than it came.
    func close() {
        guard let p = panel, isOpen else { return }
        isOpen = false
        turn += 1
        let closing = turn
        onOpenChange?(false)
        model.focus = nil
        footDrag = nil
        height.dragged = nil
        removeMonitors()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.12
            c.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self, self.turn == closing, let p = self.panel else { return }
            p.orderOut(nil)
            p.alphaValue = 1
        }
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
        // It fades in and out on its own.
        p.animationBehavior = .none
        p.isReleasedWhenClosed = false
        p.foot = { [weak self] e in self?.foot(e) == true }
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
                     focus: { [weak self] id in self?.model.focus = id },
                     toggleQuiet: { [weak self] in self?.actions?.toggleQuiet() })
    }

    private var screen: NSScreen? { anchor?.window?.screen ?? NSScreen.main }

    /// The tallest the screen allows.
    private var screenHeight: Double {
        guard let s = screen else { return 800 }
        let menuBar = s.frame.maxY - s.visibleFrame.maxY
        return s.frame.height - menuBar - 12
    }

    /// The tallest the panel may be: where its foot was left, never shorter
    /// than the shortest panel, nor taller than the screen allows.
    private var maxHeight: Double {
        let chosen = height.dragged ?? model.settings.appearance.panelHeight.map(Double.init) ?? .infinity
        return min(screenHeight, max(height.shortest, chosen))
    }

    /// The panel's height with Status, This Mac's four readings and two
    /// time zones, as this theme and text size draw them.
    private func measureShortest() -> Double {
        let h = NSHostingView(rootView: PanelRoot(model: model, actions: PanelActions(), maxHeight: { nil }, shown: model.panel.shortest))
        return h.fittingSize.height
    }

    private func layout() {
        guard let p = panel, let h = hosting else { return }
        h.layoutSubtreeIfNeeded()
        let size = h.fittingSize
        guard let s = screen else { return }
        // The glass alone gives the window a square shadow, edged in black
        // past the corners; masked, the shadow follows the panel's shape.
        h.wantsLayer = true
        h.layer?.cornerRadius = Renderers.renderer(for: model.theme).panelCornerRadius(model.theme)
        h.layer?.cornerCurve = .continuous
        h.layer?.masksToBounds = true
        let bf = anchor?.window?.frame ?? NSRect(x: s.frame.midX, y: s.visibleFrame.maxY, width: 0, height: 0)
        var x = bf.midX - size.width / 2
        x = min(max(x, s.visibleFrame.minX + 8), s.visibleFrame.maxX - size.width - 8)
        let top = min(bf.minY, s.visibleFrame.maxY) - 5
        p.setFrame(NSRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height), display: true)
    }

    // MARK: the foot

    /// The panel's foot sets its height, as a window's edge does: dragged,
    /// how tall the panel may be; double-clicked, as tall as the screen
    /// allows. Saved when the drag ends.
    private func foot(_ e: NSEvent) -> Bool {
        guard let p = panel, isOpen else { return false }
        // Where the event happened, which a frame changed since doesn't move.
        let y = e.cgEvent?.location.y ?? 0
        switch e.type {
        case .leftMouseDown where e.locationInWindow.y < Self.footBand:
            if e.clickCount > 1 {
                footDrag = nil
                model.update { $0.appearance.panelHeight = nil }
            } else {
                height.shortest = measureShortest()
                footDrag = (y, p.frame.height, false)
            }
            return true
        case .leftMouseDragged:
            guard let d = footDrag else { return false }
            footDrag?.moved = true
            height.dragged = min(screenHeight, max(height.shortest, d.height + y - d.pointer))
            layout()
            return true
        case .leftMouseUp:
            guard let d = footDrag else { return false }
            footDrag = nil
            if d.moved, let h = height.dragged {
                height.dragged = nil
                model.update { $0.appearance.panelHeight = h >= screenHeight ? nil : Int(h.rounded()) }
            }
            return true
        default:
            return false
        }
    }

    // MARK: keyboard and clicks outside

    private func installMonitors() {
        removeMonitors()
        // The system hosts the menu bar item, so a click on it reaches this
        // monitor too. That click is left to the item, which closes the
        // panel; closing here would let the item open it again.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.anchor?.window?.frame.contains(NSEvent.mouseLocation) != true else { return }
                self.close()
            }
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

    /// ↑↓ move, ↵ opens, Space leaps, Esc closes, ⌘O ⌘, ⌘Q.
    private func key(_ e: NSEvent) -> Bool {
        guard isOpen, e.window === panel else { return false }
        let cmd = e.modifierFlags.contains(.command)
        switch (e.keyCode, cmd, e.charactersIgnoringModifiers ?? "") {
        case (53, _, _): close(); return true
        case (126, false, _): move(-1); return true
        case (125, false, _): move(1); return true
        case (36, false, _), (76, false, _): activate(); return true
        case (49, false, _) where !buttonHasKeyboard: model.leaps += 1; return true
        case (_, true, "o"): actions?.openTerminal(); return true
        case (_, true, ","): actions?.openSettings(); return true
        case (_, true, "q"): actions?.quit(); return true
        default: return false
        }
    }

    /// Whether a button has the keyboard, as with Full Keyboard Access:
    /// Space presses it then.
    private var buttonHasKeyboard: Bool {
        guard let r = panel?.firstResponder else { return false }
        return r !== panel && r !== hosting
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
            text = tr("\(a.more) more in Topophany")
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

/// What the panel's height comes from besides the settings. Observed, so
/// the panel follows a change at once.
@MainActor
@Observable
final class PanelHeight {
    /// How short the panel may be made, as last measured.
    var shortest = 0.0
    /// While the foot is dragged, where it is; saved when it's let go.
    var dragged: Double?
}

final class KeyPanel: NSPanel {
    /// Takes the mouse at the panel's foot, before the views under it.
    var foot: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if foot?(event) == true { return }
        super.sendEvent(event)
    }
}

/// The panel's SwiftUI root: the theme's renderer, told what the system
/// asks for.
struct PanelRoot: View {
    var model: AppModel
    var actions: PanelActions
    var maxHeight: () -> Double?
    /// Another panel than the model's, to measure.
    var shown: PanelModel?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let s = model.settings.appearance
        let scheme: ColorScheme = s.panel == .light ? .light : s.panel == .dark ? .dark : systemScheme
        // A theme with its own appearance keeps it; the rest follow the
        // setting, or the system.
        let window: ColorScheme? = switch model.theme.appearance {
        case .light: .light
        case .dark: .dark
        case .system: s.panel == .system ? nil : scheme
        }
        let ctx = RenderContext(theme: model.theme, colorScheme: scheme, backdrop: .live, textSize: s.textSize,
                                focus: model.focus, reduceTransparency: reduceTransparency,
                                increaseContrast: contrast == .increased, maxHeight: maxHeight(), leaps: model.leaps)
        // Built anew for a new language, which L10n already has: a section
        // whose model didn't change keeps its words otherwise.
        Renderers.renderer(for: model.theme).panel(shown ?? model.panel, context: ctx)
            .id(model.settings.language)
            .environment(\.panelActions, actions)
            .environment(\.locale, L10n.locale)
            .preferredColorScheme(window)
            .overlay(alignment: .bottom) {
                // The foot, where the panel's height is dragged.
                Color.clear.frame(height: PanelController.footBand).contentShape(Rectangle())
                    .pointerStyle(.frameResize(position: .bottom))
                    .accessibilityHidden(true)
            }
    }
}
