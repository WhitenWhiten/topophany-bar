#if DEBUG
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// `-snapshot DIR`: writes the status item, the open panel and each Settings
/// tab to PNGs, as the app draws them on screen, then quits. Debug builds
/// only; for checking the real windows without screen recording.
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        UserDefaults.standard.string(forKey: "snapshot").map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
    }

    static func run(delegate: AppDelegate) {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if let image = delegate.statusItemImage { write(image, dir.appending(path: "status-item.png")) }
            delegate.openPanelForSnapshot()
            try? await Task.sleep(for: .seconds(1))
            if let w = delegate.panelWindow { write(w, dir.appending(path: "panel.png")) }
            for key in ["down", "down", "down"] {
                delegate.panelKey(key)
                try? await Task.sleep(for: .milliseconds(300))
            }
            if let w = delegate.panelWindow { write(w, dir.appending(path: "panel-focus.png")) }
            delegate.showSettings()
            for (i, name) in ["general", "appearance", "sections", "mac"].enumerated() {
                delegate.selectSettingsTab(i)
                try? await Task.sleep(for: .milliseconds(900))
                if let w = delegate.settingsWindow { write(w, dir.appending(path: "settings-\(name).png")) }
            }
            NSApp.terminate(nil)
        }
    }

    static func write(_ window: NSWindow, _ url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let cg = rep.cgImage else { return }
        write(cg, url)
    }

    static func write(_ image: NSImage, _ url: URL) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        write(cg, url)
    }

    static func write(_ cg: CGImage, _ url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
