#if DEBUG
import AppKit
import ApplicationServices
import ServiceManagement
import TopophanyKit
import TopophanyWidgets

/// Debug builds take commands as distributed notifications named
/// `io.github.whitenwhiten.topophany-bar.debug`, the command as the object:
/// for driving the real windows from a script and timing what they do.
/// Output goes to `/tmp/topophany-bar-debug/`.
///
///     settings N            show Settings on tab N, floating
///     panel | close         open or close the panel
///     tui                   open the TUI, as ⌘O does
///     key up|down|return    a key in the panel
///     type C [cmd]          C typed into the panel, through the app's event queue
///     clickitem             a click on the menu bar item
///     mac off|local|server  This Mac's mode
///     click X Y             a click in Settings, in points from its top left
///     click panel X Y       a click in the panel
///     drag X Y DY [S]       a drag of DY points, over S seconds (default 0.6)
///     trace S               Settings' frame and This Mac's mode, for S seconds
///     ax                    the open panel's accessibility tree
///     windows               each window's number and frame
///     handoff               what the widgets were last handed
///     login [on|off]        Open at login: set it, and report its status
///     language L            the language: system, en, ja or zh-Hans
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
        case "panel": d.openPanelForSnapshot()
        case "close": d.closePanel()
        case "tui": d.openTUI(focus: nil)
        case "key": if w.count > 1 { d.panelKey(w[1]) }
        case "type":
            let codes: [String: UInt16] = [",": 43, "q": 12, "o": 31]
            guard w.count > 1, let code = codes[w[1]], let win = d.panelWindow,
                  let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: w.count > 2 ? .command : [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
                                           context: nil, characters: w[1], charactersIgnoringModifiers: w[1],
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
            let panel = w.count > 1 && w[1] == "panel"
            guard let x = num(panel ? 2 : 1), let y = num(panel ? 3 : 2), let win = panel ? d.panelWindow : d.settingsWindow else { return }
            Task { await drag(win, from: CGPoint(x: x, y: y), dy: 0, seconds: 0.05, activate: !panel) }
        case "drag":
            guard let x = num(1), let y = num(2), let dy = num(3), let win = d.settingsWindow else { return }
            Task { await drag(win, from: CGPoint(x: x, y: y), dy: dy, seconds: num(4) ?? 0.6) }
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
            var lines = NSApp.windows.map { "\($0.windowNumber) \($0.isVisible ? "visible" : "hidden") \($0.frame) \($0.title)" }
            if let b = d.statusButton {
                lines.append("item image \(b.image?.size ?? .zero) button \(b.frame) inset \(b.alignmentRectInsets)")
            }
            try? lines.joined(separator: "\n").write(to: out.appending(path: "windows.txt"), atomically: true, encoding: .utf8)
        default: break
        }
    }

    /// Mouse down, moves and up, posted to the app's own queue.
    static func drag(_ win: NSWindow, from p: CGPoint, dy: Double, seconds: Double, activate: Bool = true) async {
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
                                             clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { return }
            NSApp.postEvent(e, atStart: false)
        }
        post(.leftMouseDown, p.y)
        for i in 1...steps {
            try? await Task.sleep(for: .seconds(seconds / Double(steps)))
            if dy != 0 { post(.leftMouseDragged, p.y + dy * Double(i) / Double(steps)) }
        }
        post(.leftMouseUp, p.y + dy)
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
