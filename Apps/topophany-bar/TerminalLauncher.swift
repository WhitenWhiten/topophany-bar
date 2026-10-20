import AppKit
import TopophanyEngine
import TopophanyKit
import TopophanySections
import UniformTypeIdentifiers

/// Opens the TUI in the user's terminal, on the page for an attention
/// entry when there is one.
@MainActor
enum TerminalLauncher {
    /// A terminal the TUI can open in, and how it's handed the TUI.
    struct TerminalApp: Hashable, Identifiable {
        var id: String
        var name: String
        var url: URL
        var launch: Launch

        var icon: NSImage {
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 16, height: 16)
            return image
        }
    }

    enum Launch: Hashable {
        /// Opens the script as it opens a `.command` file.
        case script
        /// Runs it in a new instance: these arguments, then the script.
        case arguments([String])
    }

    /// Shell scripts a terminal runs when it opens them.
    static let scriptType = UTType("com.apple.terminal.shell-script") ?? .shellScript

    /// Well-known terminals by bundle identifier, offered when installed.
    /// Each opens the script if it says it opens shell scripts, and
    /// otherwise runs it with the arguments it takes for a program; one
    /// with neither is left out.
    static let known: [(id: String, arguments: [String]?)] = [
        ("com.apple.Terminal", nil),
        ("com.googlecode.iterm2", nil),
        ("com.mitchellh.ghostty", ["-e"]),
        ("com.github.wez.wezterm", ["start", "--"]),
        ("net.kovidgoyal.kitty", []),
        ("org.alacritty", ["-e"]),
        ("com.raphaelamorim.rio", ["-e"]),
        ("dev.warp.Warp-Stable", nil),
        ("co.zeit.hyper", nil),
    ]

    /// The installed terminals, in `known`'s order, then the app chosen
    /// with Other… if it isn't one of them.
    static func terminals(chosen: String = "") -> [TerminalApp] {
        let ws = NSWorkspace.shared
        let openers = Set(ws.urlsForApplications(toOpen: scriptType).compactMap { Bundle(url: $0)?.bundleIdentifier })
        var out: [TerminalApp] = known.compactMap { k in
            guard let url = ws.urlForApplication(withBundleIdentifier: k.id) else { return nil }
            let launch: Launch
            if openers.contains(k.id) { launch = .script } else if let a = k.arguments { launch = .arguments(a) } else { return nil }
            return TerminalApp(id: k.id, name: name(url), url: url, launch: launch)
        }
        if !chosen.isEmpty, !out.contains(where: { $0.id == chosen }),
           let url = ws.urlForApplication(withBundleIdentifier: chosen) {
            out.append(TerminalApp(id: chosen, name: name(url), url: url, launch: .script))
        }
        return out
    }

    /// The terminal the TUI opens in: the one chosen, if it's still
    /// installed; else the system's own for scripts, if that's a terminal;
    /// else Terminal.
    static func terminal(chosen: String) -> TerminalApp? {
        let all = terminals(chosen: chosen)
        if let t = all.first(where: { $0.id == chosen }) { return t }
        let system = NSWorkspace.shared.urlForApplication(toOpen: scriptType).flatMap { Bundle(url: $0)?.bundleIdentifier }
        return all.first { $0.id == system } ?? all.first { $0.id == "com.apple.Terminal" } ?? all.first
    }

    /// An app's name as the Finder shows it.
    static func name(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// The TUI tab for an attention entry's kind, as `topo --page` names them.
    static func page(for kind: String) -> String? {
        switch kind {
        case "incident": "incidents"
        case "path": "paths"
        case "service": "services"
        case "node": "servers"
        case "check": "checks"
        case "observer": "observers"
        case "endpoint", "link": "topology"
        default: nil
        }
    }

    /// `topo`'s arguments for the TUI, viewing what the bar views.
    static func arguments(_ s: TopophanyKit.Settings, focus: AttentionSection.Item?) -> [String] {
        var args: [String] = []
        if s.topo.source == "preview" {
            args += ["preview", "--scenario", String(s.topo.scenario ?? 0)]
        } else if !s.topo.profile.isEmpty {
            args += ["--profile", s.topo.profile]
        }
        if !s.topo.observer.isEmpty { args += ["--observer", s.topo.observer] }
        if let focus, let page = page(for: focus.kind) { args += ["--page", page] }
        return args
    }

    static func open(model: AppModel, focus: AttentionSection.Item?) {
        let path: String
        if case .running(let r) = model.engineStatus, model.fixture == nil {
            path = r.path
        } else if case .success(let found) = TopoLocator(setting: model.effectiveSettings.topo.path, downloads: model.downloads).locate() {
            path = found.path
        } else {
            NSSound.beep()
            return
        }
        let command = ([path] + arguments(model.effectiveSettings, focus: focus)).map(quote).joined(separator: " ")
        // The script removes itself before it becomes topo.
        let script = "#!/bin/sh\nrm -f \"$0\"\nclear\nexec \(command)\n"
        let dir = FileManager.default.temporaryDirectory.appending(path: "topophany-bar")
        let url = dir.appending(path: "topo-\(UUID().uuidString.prefix(8)).command")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            NSSound.beep()
            return
        }
        guard let app = terminal(chosen: model.settings.terminal) else { NSSound.beep(); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let failed: @Sendable (Any?, (any Error)?) -> Void = { _, error in
            if error != nil { Task { @MainActor in NSSound.beep() } }
        }
        switch app.launch {
        case .script:
            NSWorkspace.shared.open([url], withApplicationAt: app.url, configuration: config, completionHandler: failed)
        case .arguments(let a):
            // Arguments reach only a new instance.
            config.arguments = a + [url.path]
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: app.url, configuration: config, completionHandler: failed)
        }
    }

    /// Single-quotes a word for the shell.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
