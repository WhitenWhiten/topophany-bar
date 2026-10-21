#if DEBUG
import AppKit
import ApplicationServices
import ServiceManagement
import TopophanyEngine
import TopophanyKit
import TopophanyWidgets

/// Debug builds take commands as distributed notifications named
/// `io.github.whitenwhiten.topophany-bar.debug`, the command as the object:
/// for driving the real windows from a script and timing what they do.
/// Output goes to `/tmp/topophany-bar-debug/`.
///
///     settings N            show Settings on tab N, floating
///     about                 show About Topophany, floating
///     mainmenu              the app's menu bar, as text
///     panel | close         open or close the panel
///     tui                   open the TUI, as ⌘O does
///     key up|down|return|escape
///                           a key in the panel
///     type [settings|#N] C [cmd]
///                           C typed into the panel, Settings or window N,
///                           through the app's event queue; `space` for a space
///     clickitem             a click on the menu bar item
///     mac off|local|server  This Mac's mode
///     click X Y [N]         a click in Settings, in points from its top left;
///                           N in a row for a double click
///     click panel X Y [N]   a click in the panel
///     drag [panel] X Y DY [S]
///                           a drag of DY points in Settings or the panel,
///                           over S seconds (default 0.6)
///     trace S               Settings' frame and This Mac's mode, for S seconds
///     ax                    the open panel's accessibility tree
///     windows               each window's number and frame, the key window,
///                           and whether the app is active
///     handoff               what the widgets were last handed
///     login [on|off]        Open at login: set it, and report its status
///     language L            the language: system, en, ja or zh-Hans
///     fixture NAME          replay another fixture, in a copy launched
///                           with one
///     download latest|tested
///                           download topo, as the Download button does
///     topos                 where topo was found, every copy and the
///                           download, to topos.txt
///     use PATH|auto         run that topo, or search again
///     deletedownload V      delete the downloaded topo V
///     menu                  the menu bar item's right-click menu, as text
///     itemshot              the menu bar item as last drawn, to item.png
///     views                 the open panel's AppKit views and their frames,
///                           and its first responder
///     scroll [panel|#N] X Y DY [DX]
///                           a scroll of DY (and DX) points at X Y in
///                           Settings, the panel or window N (a popover),
///                           as a trackpad sends one, the app's own scroll
///                           monitor first, as the map's zoom takes it;
///                           how far the scroll view under it moved, to
///                           scroll.txt
///
/// A command starting with `@PID` goes to that running copy only.
@MainActor
enum DebugDriver {
    static let name = Notification.Name("io.github.whitenwhiten.topophany-bar.debug")
    static let out = URL(filePath: "/tmp/topophany-bar-debug")

    static func start(delegate: AppDelegate) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { run(command, delegate) }
        }
    }

    static func run(_ command: String, _ d: AppDelegate) {
        var w = command.split(separator: " ").map(String.init)
        if let to = w.first, to.hasPrefix("@") {
            guard to == "@\(getpid())" else { return }
            w.removeFirst()
        }
        guard let verb = w.first else { return }
        func num(_ i: Int) -> Double? { i < w.count ? Double(w[i]) : nil }
        switch verb {
        case "settings":
            d.showSettings()
            d.selectSettingsTab(Int(num(1) ?? 0))
            // Above other apps' windows, for recording the screen.
            d.settingsWindow?.level = .floating
            d.settingsWindow?.orderFrontRegardless()
        case "about":
            d.showAbout()
            for win in NSApp.windows where win.isVisible && win.styleMask.contains(.titled) && win !== d.settingsWindow {
                win.level = .floating
                win.orderFrontRegardless()
            }
        case "mainmenu":
            func keys(_ i: NSMenuItem) -> String {
                guard !i.keyEquivalent.isEmpty else { return "" }
                let m = i.keyEquivalentModifierMask
                return " " + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "")
                    + (m.contains(.command) ? "⌘" : "") + i.keyEquivalent.uppercased()
            }
            var lines = NSApp.mainMenu == nil ? ["none"] : []
            for top in NSApp.mainMenu?.items ?? [] {
                lines.append(top.title)
                lines += (top.submenu?.items ?? []).map { "  " + ($0.isSeparatorItem ? "—" : $0.title + keys($0)) }
            }
            try? lines.joined(separator: "\n").write(to: out.appending(path: "mainmenu.txt"), atomically: true, encoding: .utf8)
        case "panel": d.openPanelForSnapshot()
        case "close": d.closePanel()
        case "tui": d.openTUI(focus: nil)
        case "key": if w.count > 1 { d.panelKey(w[1]) }
        case "type":
            let codes: [String: UInt16] = [",": 43, "q": 12, "o": 31, "m": 46, "space": 49,
                                           "a": 0, "c": 8, "h": 4, "v": 9, "w": 13, "x": 7, "z": 6]
            let settings = w.count > 1 && w[1] == "settings"
            let number = w.count > 1 && w[1].hasPrefix("#") ? Int(w[1].dropFirst()) : nil
            let k = settings || number != nil ? 1 : 0
            let target = number.flatMap { n in NSApp.windows.first { $0.windowNumber == n } }
            guard w.count > 1 + k, let code = codes[w[1 + k]],
                  let win = target ?? (settings ? d.settingsWindow : d.panelWindow) else { return }
            let c = w[1 + k] == "space" ? " " : w[1 + k]
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: w.count > 2 + k ? .command : [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
                                           context: nil, characters: c, charactersIgnoringModifiers: c,
                                           isARepeat: false, keyCode: code) else { return }
            NSApp.postEvent(e, atStart: false)
        case "clickitem":
            guard let b = d.statusButton, let win = b.window else { return }
            let at = b.convert(NSPoint(x: b.bounds.midX, y: b.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                              pressure: type == .leftMouseUp ? 0 : 1) { NSApp.postEvent(e, atStart: false) }
            }
        case "click":
            // `click #N X Y` clicks in window N, such as a popover.
            let panel = w.count > 1 && w[1] == "panel"
            let number = w.count > 1 && w[1].hasPrefix("#") ? Int(w[1].dropFirst()) : nil
            let k = panel || number != nil ? 1 : 0
            let target = number.flatMap { n in NSApp.windows.first { $0.windowNumber == n } }
            guard let x = num(1 + k), let y = num(2 + k),
                  let win = target ?? (panel ? d.panelWindow : d.settingsWindow) else { return }
            Task {
                for n in 1...max(1, Int(num(3 + k) ?? 1)) {
                    await drag(win, from: CGPoint(x: x, y: y), dy: 0, seconds: 0.05, activate: k == 0 && n == 1, clicks: n)
                }
            }
        case "drag":
            let panel = w.count > 1 && w[1] == "panel"
            let k = panel ? 1 : 0
            guard let x = num(1 + k), let y = num(2 + k), let dy = num(3 + k), let win = panel ? d.panelWindow : d.settingsWindow else { return }
            Task { await drag(win, from: CGPoint(x: x, y: y), dy: dy, seconds: num(4 + k) ?? 0.6, activate: !panel) }
        case "views":
            var lines: [String] = []
            func walk(_ v: NSView, _ depth: Int) {
                let f = v.convert(v.bounds, to: nil)
                lines.append(String(repeating: "  ", count: depth) + "\(type(of: v)) \(f)\(v.isHidden ? " hidden" : "")")
                for c in v.subviews { walk(c, depth + 1) }
            }
            if let v = d.panelWindow?.contentView { walk(v, 0) }
            lines.append("first responder: " + (d.panelWindow?.firstResponder.map { "\(type(of: $0))" } ?? "none"))
            try? lines.joined(separator: "\n").write(to: out.appending(path: "views.txt"), atomically: true, encoding: .utf8)
        case "scroll":
            let panel = w.count > 1 && w[1] == "panel"
            let number = w.count > 1 && w[1].hasPrefix("#") ? Int(w[1].dropFirst()) : nil
            let k = panel || number != nil ? 1 : 0
            let target = number.flatMap { n in NSApp.windows.first { $0.windowNumber == n } }
            guard let x = num(1 + k), let y = num(2 + k), let dy = num(3 + k),
                  let win = target ?? (panel ? d.panelWindow : d.settingsWindow) else { return }
            Task { await scroll(win, at: CGPoint(x: x, y: y), dy: dy, dx: num(4 + k) ?? 0, panelOf: panel ? d : nil) }
        case "trace":
            guard let win = d.settingsWindow else { return }
            trace(win, model: d.model, seconds: num(1) ?? 2)
        case "login":
            if w.count > 1 { d.model.update { $0.openAtLogin = w[1] == "on" } }
            let status = switch SMAppService.mainApp.status {
            case .enabled: "enabled"
            case .notRegistered: "not registered"
            case .requiresApproval: "requires approval"
            case .notFound: "not found"
            @unknown default: "unknown"
            }
            try? "\(status) (setting \(d.model.settings.openAtLogin))".write(to: out.appending(path: "login.txt"), atomically: true, encoding: .utf8)
        case "download":
            d.model.download(w.count > 1 && w[1] == "tested" ? .tested : .latest)
        case "use":
            if w.count > 1 { d.model.use(w[1] == "auto" ? "" : w[1]) }
        case "deletedownload":
            if w.count > 1, let i = d.model.downloaded.first(where: { $0.version == w[1] }) { d.model.deleteDownload(i) }
        case "topos":
            var lines = ["setting \(d.model.settings.topo.path.isEmpty ? "(search)" : d.model.settings.topo.path)",
                         "located \(String(describing: d.model.located))", "engine \(d.model.engineStatus)",
                         "fetch \(d.model.fetch)", "offer \(String(describing: d.model.panel.download))",
                         "downloads \(d.model.downloads.directory.path)"]
            lines += d.model.downloaded.map { "downloaded \($0.version) \($0.path)" }
            lines += d.model.candidates.map { "candidate \(TopoRow.title($0)) · \($0.origin) · \($0.path)" }
            try? lines.joined(separator: "\n").write(to: out.appending(path: "topos.txt"), atomically: true, encoding: .utf8)
        case "fixture":
            if w.count > 1, let s = FixtureEngine.Scenario(rawValue: w[1]) { d.model.replay(s) }
        case "menu":
            let lines = d.itemMenu().items.map { i in
                i.isSeparatorItem ? "—" : "\(i.state == .on ? "✓" : " ") \(i.title)\(i.isEnabled ? "" : " (disabled)")"
            }
            try? lines.joined(separator: "\n").write(to: out.appending(path: "menu.txt"), atomically: true, encoding: .utf8)
        case "itemshot":
            if let image = d.statusItemImage { DebugSnapshots.write(image, out.appending(path: "item.png")) }
        case "language":
            if w.count > 1, let l = TopophanyKit.Settings.Language(rawValue: w[1]) { d.model.update { $0.language = l } }
        case "handoff":
            let store = HandoffStore(appGroup: HandoffStore.bundleAppGroup)
            var lines = ["group \(HandoffStore.bundleAppGroup ?? "none")", "directory \(store.directory?.path ?? "none")"]
            if let h = store.read() {
                lines += ["written \(h.writtenAt)", "frame \(h.frame?.count ?? 0) bytes", "running \(h.engineRunning)",
                          "verdict \(h.panel().status.title)"]
            } else {
                lines.append("no hand-off")
            }
            try? lines.joined(separator: "\n").write(to: out.appending(path: "handoff.txt"), atomically: true, encoding: .utf8)
        case "ax":
            // What VoiceOver reads in the panel, asked for as an assistive
            // app asks: each element's role, label and value, in order.
            var lines: [String] = []
            func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
                var v: AnyObject?
                return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
            }
            func walk(_ e: AXUIElement, _ depth: Int) {
                guard depth < 30 else { return }
                let role = attr(e, kAXRoleAttribute) as? String ?? "?"
                let label = attr(e, kAXDescriptionAttribute) as? String ?? attr(e, kAXTitleAttribute) as? String ?? ""
                let value = attr(e, kAXValueAttribute).map { "\($0)" } ?? ""
                if !label.isEmpty || !value.isEmpty {
                    lines.append(String(repeating: "  ", count: depth) + "\(role) “\(label)” \(value)")
                }
                for c in attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(c, depth + 1) }
            }
            let app = AXUIElementCreateApplication(getpid())
            var windows: AnyObject?
            let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
            lines.append("windows: \(err.rawValue)")
            for w in windows as? [AXUIElement] ?? [] { walk(w, 0) }
            try? lines.joined(separator: "\n").write(to: out.appending(path: "ax.txt"), atomically: true, encoding: .utf8)
        case "windows":
            var lines = NSApp.windows.map {
                "\($0.windowNumber) \($0.isVisible ? "visible" : "hidden")\($0.isKeyWindow ? " key" : "") \($0.frame) \($0.title)"
            }
            lines.append("app \(NSApp.isActive ? "active" : "inactive"), \(NSApp.activationPolicy() == .regular ? "regular" : "accessory")")
            if let b = d.statusButton {
                lines.append("item image \(b.image?.size ?? .zero) button \(b.frame) inset \(b.alignmentRectInsets)")
            }
            try? lines.joined(separator: "\n").write(to: out.appending(path: "windows.txt"), atomically: true, encoding: .utf8)
        default: break
        }
    }

    /// Mouse down, moves and up, posted to the app's own queue; `clicks`
    /// is the click's place in a run of them.
    static func drag(_ win: NSWindow, from p: CGPoint, dy: Double, seconds: Double, activate: Bool = true, clicks: Int = 1) async {
        let steps = max(1, Int(seconds * 60))
        if activate {
            NSApp.activate()
            win.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(200))
        }
        func post(_ type: NSEvent.EventType, _ y: Double) {
            let at = NSPoint(x: p.x, y: win.frame.height - y)
            guard let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: win.windowNumber, context: nil, eventNumber: 0,
                                             clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1) else { return }
            NSApp.postEvent(e, atStart: false)
        }
        post(.leftMouseDown, p.y)
        for i in 1...steps {
            try? await Task.sleep(for: .seconds(seconds / Double(steps)))
            if dy != 0 { post(.leftMouseDragged, p.y + dy * Double(i) / Double(steps)) }
        }
        post(.leftMouseUp, p.y + dy)
    }

    /// Scroll wheel events at `p` (points from the window's top left), in a
    /// few steps, to the view there, or first to the panel's own scroll
    /// monitor when `d` is given; then where the scroll view under `p` was
    /// before and after.
    static func scroll(_ win: NSWindow, at p: CGPoint, dy: Double, dx: Double, panelOf d: AppDelegate? = nil) async {
        let local = NSPoint(x: p.x, y: win.frame.height - p.y)
        let screen = win.convertPoint(toScreen: local)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        func scrollView() -> NSScrollView? {
            var v = win.contentView?.hitTest(local)
            while let view = v, !(view is NSScrollView) { v = view.superview }
            return v as? NSScrollView
        }
        let before = scrollView()?.contentView.bounds.origin
        let steps = 6
        var seen = ""
        for _ in 0..<steps {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                   wheel1: Int32(-dy / Double(steps)), wheel2: Int32(-dx / Double(steps)), wheel3: 0) else { return }
            cg.location = CGPoint(x: screen.x, y: top - screen.y)
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(win.windowNumber))
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(win.windowNumber))
            if let e = NSEvent(cgEvent: cg), d?.panelScroll(e) == true {
                seen = "to the map dy \(e.scrollingDeltaY)"
            } else if let e = NSEvent(cgEvent: cg) {
                // Made from a CGEvent, it has no window, so it goes to the
                // view under `p` as the window's own hit test would send it.
                let view = win.contentView?.hitTest(local)
                seen = "to \(view.map { String(describing: type(of: $0)) } ?? "none") dy \(e.scrollingDeltaY)"
                view?.scrollWheel(with: e)
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        try? await Task.sleep(for: .milliseconds(300))
        let sv = scrollView()
        let lines = [seen, "local \(local)", "view \(sv.map { String(describing: type(of: $0)) } ?? "none")",
                     "before \(before.map { "\($0.x) \($0.y)" } ?? "-")",
                     "after \(sv.map { "\($0.contentView.bounds.origin.x) \($0.contentView.bounds.origin.y)" } ?? "-")"]
        try? lines.joined(separator: "\n").write(to: out.appending(path: "scroll.txt"), atomically: true, encoding: .utf8)
    }

    /// Writes "t height y preferred mode" lines, t in milliseconds from the start.
    static func trace(_ win: NSWindow, model: AppModel, seconds: Double) {
        let start = ProcessInfo.processInfo.systemUptime
        Task { @MainActor in
            var lines: [String] = []
            while ProcessInfo.processInfo.systemUptime - start < seconds {
                let t = ProcessInfo.processInfo.systemUptime - start
                let content = win.contentViewController?.preferredContentSize.height ?? 0
                lines.append(String(format: "%5.0f %6.1f %6.1f %6.1f ", t * 1000, win.frame.height, win.frame.minY, content)
                             + model.settings.sections.mac.mode.rawValue)
                try? await Task.sleep(for: .milliseconds(8))
            }
            try? lines.joined(separator: "\n").write(to: out.appending(path: "trace.txt"), atomically: true, encoding: .utf8)
        }
    }
}
#endif
