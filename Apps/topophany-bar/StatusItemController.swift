import AppKit
import QuartzCore
import SwiftUI
import TopophanySections
import TopophanyThemes

/// The menu bar item: the verdict, drawn by the theme's renderer in the
/// menu bar's ink. While the panel is open it sits on a pressed capsule,
/// which the system doesn't draw for an item without a menu.
///
/// It keeps the item's clock: the turn, which runs while what the item
/// shows is current, and the latest change while it settles. Nothing moves
/// while the user turned motion off, or Reduce Motion or Low Power Mode is
/// on; nothing is drawn for it while the displays sleep or the item can't
/// be seen.
///
/// It draws as little as it can. Frames go to layers of the item's own;
/// the button's image only holds the item's size, since handing the system
/// a new image costs it many times what a layer's contents cost. This
/// Mac's readings have a layer of their own, drawn once a sample. A turn
/// repeats every step, so its frames are kept, and once a step's are all
/// drawn the system plays them on its own until something changes.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let onClick: (NSStatusBarButton) -> Void
    private var appearanceWatch: NSKeyValueObservation?
    /// One renderer for every frame, and one for the readings: each keeps
    /// its view graph, so a frame redraws only what moved.
    private let renderer = ImageRenderer(content: AnyView(EmptyView()))
    private let readingsRenderer = ImageRenderer(content: AnyView(EmptyView()))
    private var readingsKey: ReadingsKey?
    private let frameView = FrameView()
    /// The latest frame, for snapshots.
    private(set) var frame: NSImage?
    /// Frames of the turn by their place in a step, for what `key` draws.
    private var frames: [Int: CGImage] = [:]
    private var key: FrameKey?
    /// Frames in one step of the turn: one a display frame at 15 a second.
    static let framesPerStep = 36

    private var turn = StatusItemTurn()
    /// When the system started playing the turn, and where it was then.
    private var playing: (phase: Double, at: TimeInterval)?
    /// What the item showed before its latest change, and when it changed.
    private var change: (from: StatusItemModel, at: TimeInterval)?
    private var shown: StatusItemModel?
    private var link: CADisplayLink?
    private var linkRate: Float = 0
    private var lastTick: TimeInterval?
    private var screensAsleep = false
    private var hidden = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

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
                MainActor.assumeIsolated { self?.update() }
            }
            frameView.frame = b.bounds
            frameView.autoresizingMask = [.width, .height]
            b.addSubview(frameView)
        }
        item.autosaveName = "topophany-bar"
        watch()
        update()
    }

    /// Built on each right-click: what the item's menu offers now.
    var contextMenu: (() -> NSMenu?)?

    @objc private func clicked() {
        guard let b = item.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp, let menu = contextMenu?() {
            // Only the item's own menu is placed under it and drawn pressed
            // by the system, so it holds this one while it's open.
            item.menu = menu
            b.performClick(nil)
            item.menu = nil
        } else {
            onClick(b)
        }
    }

    var button: NSStatusBarButton? { item.button }

    var pressed = false {
        didSet { if pressed != oldValue { update() } }
    }

    private var pressView: NSView?

    /// The capsule spans the item's margins too, which are outside the
    /// button, so it sits behind the button in the item's window.
    private func showPressed(dark: Bool) {
        guard let b = item.button, let host = b.superview else { return }
        let v = pressView ?? NSView()
        if v.superview !== host {
            v.wantsLayer = true
            v.layer?.cornerRadius = 6
            v.layer?.cornerCurve = .continuous
            v.autoresizingMask = [.width, .minYMargin, .maxYMargin]
            host.addSubview(v, positioned: .below, relativeTo: b)
            pressView = v
        }
        v.frame = NSRect(x: 0, y: ((host.bounds.height - 22) / 2).rounded(), width: host.bounds.width, height: 22)
        v.layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.1)).cgColor
        v.isHidden = !pressed
    }

    // MARK: motion

    /// Whether the item may move at all now.
    private var mayMove: Bool {
        model.statusItem.motion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Whether the turn runs steadily, nothing else moving: the system can
    /// play its frames.
    private var steady: Bool {
        mayMove && change == nil && model.statusItem.activity == .live && turn.velocity == StatusItemTurn.speed
    }

    /// Frames a second the app draws now; 0 while nothing moves or the
    /// system plays the turn.
    private func framesWanted(at now: TimeInterval) -> Float {
        guard mayMove, !screensAsleep, !hidden, playing == nil else { return 0 }
        if let c = change, now - c.at < StatusItemMotion.changeLength { return 60 }
        let m = model.statusItem
        return m.activity == .live || m.activity == .connecting || turn.isMoving ? 15 : 0
    }

    private func schedule(at now: TimeInterval) {
        if playing == nil, steady, frames.count == Self.framesPerStep {
            frameView.play((0..<Self.framesPerStep).compactMap { frames[$0] }, from: turn.phase, period: 1 / StatusItemTurn.speed)
            playing = (turn.phase, now)
        }
        let rate = framesWanted(at: now)
        guard rate > 0, let b = item.button else {
            link?.invalidate()
            link = nil
            lastTick = nil
            return
        }
        if link == nil {
            let l = b.displayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
            linkRate = 0
        }
        if rate != linkRate {
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(8, rate), maximum: rate, preferred: rate)
            linkRate = rate
        }
    }

    /// Takes the turn back from the system, where it has got to by now.
    private func stopPlaying(at now: TimeInterval) {
        guard let p = playing else { return }
        playing = nil
        turn.run(for: now - p.at)
        frameView.stopPlaying()
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick.map { now - $0 } ?? 0
        lastTick = now
        turn.advance(by: dt, turning: mayMove && model.statusItem.activity == .live)
        if let c = change, now - c.at >= StatusItemMotion.changeLength { change = nil }
        draw(at: now)
        schedule(at: now)
    }

    private func watch() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
            let o = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { body() }
            }
            observers.append((center, o))
        }
        on(ws, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.screensAsleep = true
            self?.update()
        }
        on(ws, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.screensAsleep = false
            self?.update()
        }
        // Reduce Motion or Low Power Mode on: `update` stills the item.
        on(ws, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in self?.update() }
        on(nc, .NSProcessInfoPowerStateDidChange) { [weak self] in self?.update() }
        on(nc, NSWindow.didChangeBackingPropertiesNotification) { [weak self] in self?.update() }
        // Any window's: the item's own is the menu bar's, hidden with it.
        on(nc, NSWindow.didChangeOcclusionStateNotification) { [weak self] in
            guard let self, let w = self.item.button?.window else { return }
            let hidden = !w.occlusionState.contains(.visible)
            guard hidden != self.hidden else { return }
            self.hidden = hidden
            self.update()
        }
    }

    // MARK: drawing

    func update() {
        let now = CACurrentMediaTime()
        let m = model.statusItem
        if let s = shown, s.mark != m.mark || s.text != m.text || s.tuiText != m.tuiText || s.count != m.count {
            change = mayMove ? (s, now) : nil
        }
        shown = m
        if !steady { stopPlaying(at: now) }
        if !mayMove {
            turn.rest()
            change = nil
        }
        draw(at: now)
        schedule(at: now)
    }

    private func draw(at now: TimeInterval) {
        guard let b = item.button else { return }
        let m = model.statusItem
        let theme = model.theme
        let dark = b.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let scale = b.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let renderer = Renderers.renderer(for: theme)
        func context(_ motion: StatusItemMotion) -> StatusItemContext {
            StatusItemContext(theme: theme, menuBarIsDark: dark, motion: motion)
        }

        // The readings, once a sample.
        let rk = ReadingsKey(readings: m.readings, language: L10n.localization, theme: theme.id, dark: dark, scale: scale)
        if rk != readingsKey {
            readingsKey = rk
            var readings: CGImage?
            if let view = renderer.statusItemParts(m, context: context(.still)).readings {
                readingsRenderer.content = view
                readingsRenderer.scale = scale
                readings = readingsRenderer.cgImage
            }
            frameView.readings = readings
        }

        // The rest: between changes, and with no spinner, a frame is its
        // place in the turn's step alone.
        var drawn = m
        drawn.accessibilityLabel = ""
        drawn.readings = []
        let k = FrameKey(model: drawn, theme: theme.id, dark: dark, scale: scale)
        if k != key {
            key = k
            frames.removeAll()
            stopPlaying(at: now)
        }
        if playing == nil {
            let n = Self.framesPerStep
            let place = (Int((turn.phase * Double(n)).rounded()) % n + n) % n
            let moves = mayMove && !screensAsleep && !hidden
            let settled = change == nil && !(moves && m.activity == .connecting)
            let cg: CGImage
            if settled, let kept = frames[place] {
                cg = kept
            } else {
                let motion = StatusItemMotion(moves: moves, turn: Double(place) / Double(n), time: now,
                                              change: change.map { .init(from: $0.from, age: now - $0.at) })
                let parts = renderer.statusItemParts(drawn, context: context(motion))
                frameView.spacing = parts.spacing
                self.renderer.content = parts.item
                self.renderer.scale = scale
                guard let fresh = self.renderer.cgImage else { return }
                cg = fresh
                if settled { frames[place] = fresh }
            }
            frameView.show(cg, scale: scale)
        }
        let size = frameView.size
        if b.image?.size != size {
            b.image = NSImage(size: size, flipped: false) { _ in true }
        }
        frame = frameView.snapshot
        showPressed(dark: dark)
        if b.accessibilityLabel() != m.accessibilityLabel {
            b.setAccessibilityLabel(m.accessibilityLabel)
            b.toolTip = m.accessibilityLabel
        }
    }
}

/// What the readings layer shows.
private struct ReadingsKey: Equatable {
    var readings: [MenuBarReading]
    /// Their labels' language.
    var language: String
    var theme: String
    var dark: Bool
    var scale: CGFloat
}

/// What a kept frame shows, but for its place in the turn.
private struct FrameKey: Equatable {
    var model: StatusItemModel
    var theme: String
    var dark: Bool
    var scale: CGFloat
}

/// Shows the item's frames: the readings' layer, then the rest's, centered
/// as the button would center its image. It takes no clicks; the button
/// does.
private final class FrameView: NSView {
    private let readingsLayer = CALayer()
    private let itemLayer = CALayer()
    private var item: CGImage?
    private var scale: CGFloat = 2

    /// This Mac's readings, drawn; `nil` for none.
    var readings: CGImage? {
        didSet { if readings !== oldValue { update() } }
    }
    /// Between the readings and the rest.
    var spacing: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [readingsLayer, itemLayer] {
            l.contentsGravity = .resize
            layer?.addSublayer(l)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ image: CGImage, scale: CGFloat) {
        guard image !== item || scale != self.scale else { return }
        item = image
        self.scale = scale
        update()
    }

    /// Plays a step's frames over and over from `phase`, one step every
    /// `period` seconds, until stopped.
    func play(_ frames: [CGImage], from phase: Double, period: Double) {
        guard !frames.isEmpty else { return }
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = frames
        a.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        a.calculationMode = .discrete
        a.duration = period
        a.repeatCount = .infinity
        a.timeOffset = (phase - phase.rounded(.down)) * period
        itemLayer.add(a, forKey: "turn")
    }

    func stopPlaying() {
        itemLayer.removeAnimation(forKey: "turn")
    }

    private func points(_ image: CGImage?) -> NSSize {
        image.map { NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale) } ?? .zero
    }

    /// Both parts and the room between them.
    var size: NSSize {
        let r = points(readings), i = points(item)
        return NSSize(width: r.width + (readings == nil ? 0 : spacing) + i.width, height: max(r.height, i.height))
    }

    /// Both parts in one image, as the menu bar shows them.
    var snapshot: NSImage? {
        guard let item else { return nil }
        let r = points(readings), i = points(item), all = size
        return NSImage(size: all, flipped: false) { [readings] _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            if let readings { c.draw(readings, in: CGRect(x: 0, y: (all.height - r.height) / 2, width: r.width, height: r.height)) }
            c.draw(item, in: CGRect(x: all.width - i.width, y: (all.height - i.height) / 2, width: i.width, height: i.height))
            return true
        }
    }

    override func layout() {
        super.layout()
        update()
    }

    private func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = points(readings), i = points(item), all = size
        // In the middle, on whole pixels.
        let x = ((bounds.width - all.width) / 2 * scale).rounded() / scale
        let y = ((bounds.height - all.height) / 2 * scale).rounded() / scale
        readingsLayer.contents = readings
        readingsLayer.contentsScale = scale
        readingsLayer.frame = CGRect(x: x, y: y + (all.height - r.height) / 2, width: r.width, height: r.height)
        itemLayer.contents = item
        itemLayer.contentsScale = scale
        itemLayer.frame = CGRect(x: x + all.width - i.width, y: y + (all.height - i.height) / 2, width: i.width, height: i.height)
        CATransaction.commit()
    }
}
