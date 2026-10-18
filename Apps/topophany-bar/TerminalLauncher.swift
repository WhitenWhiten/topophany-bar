import AppKit
import TopophanyEngine
import TopophanyKit
import TopophanySections
import UniformTypeIdentifiers

/// Opens the TUI in the user's terminal, on the page for an attention
/// entry when there is one.
@MainActor
enum TerminalLauncher {
    struct App: Hashable, Identifiable {
        var id: String
        var name: String
        var url: URL
    }

    /// Shell scripts a terminal runs when it opens them.
    static let scriptType = UTType("com.apple.terminal.shell-script") ?? .shellScript

    /// The apps that say they run shell scripts, the system's choice first.
    static func apps() -> [App] {
        let ws = NSWorkspace.shared
        let preferred = ws.urlForApplication(toOpen: scriptType)
        var urls = ws.urlsForApplications(toOpen: scriptType)
        if let preferred { urls.removeAll { $0 == preferred }; urls.insert(preferred, at: 0) }
        var seen = Set<String>()
        return urls.compactMap { url in
            guard let b = Bundle(url: url), let id = b.bundleIdentifier, seen.insert(id).inserted else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return App(id: id, name: name, url: url)
        }
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
        if case .running(let r) = model.engineStatus {
            path = r.path
        } else if case .success(let found) = TopoLocator(setting: model.effectiveSettings.topo.path).locate() {
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
        let chosen = apps().first { $0.id == model.settings.terminal } ?? apps().first
        guard let app = chosen else { NSSound.beep(); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app.url, configuration: config)
    }

    /// Single-quotes a word for the shell.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
