import Foundation

/// The themes the app can draw with. The built-in ones are JSON compiled
/// in, read and validated exactly as a theme file would be. Loading user
/// theme files is designed but off in this release.
public struct ThemeStore: Sendable {
    public enum LoadError: Error, Sendable, Hashable, CustomStringConvertible {
        case unreadable(String)
        case refused([ThemeValidator.Problem])

        public var description: String {
            switch self {
            case .unreadable(let why): "can't be read: \(why)"
            case .refused(let p): p.map(\.description).joined(separator: "; ")
            }
        }
    }

    public static let nativeJSON = #"""
    {"schema": 1, "id": "native", "name": "Native", "renderer": "cards", "appearance": "system",
     "tokens": {}, "font": {"family": "SF Pro", "size": 13}}
    """#

    /// The TUI's palette (internal/tui/theme.go).
    public static let terminalJSON = #"""
    {"schema": 1, "id": "terminal", "name": "Terminal", "renderer": "cells", "appearance": "dark",
     "tokens": {
       "ink": "#0A1016", "inkHigh": "#0F1820", "selection": "#112C34", "key": "#1A2B36", "line": "#243443", "track": "#16232D",
       "text": "#D5DEE7", "muted": "#8393A3", "faint": "#4A5868", "glow": "#F0FDFA", "accent": "#5EEAD4", "accent2": "#7DD3FC",
       "kind": "#FDA4AF", "up": "#4ADE80", "warning": "#FBBF24", "down": "#F87171", "unknown": "#6B7A8C"},
     "font": {"family": "SF Mono", "size": 12}}
    """#

    /// Every built-in theme, through the same path a file takes.
    public static let builtIn: [Theme] = [nativeJSON, terminalJSON].map { json in
        switch load(Data(json.utf8)) {
        case .success(let t): return t
        case .failure(let e): fatalError("built-in theme refused: \(e)")
        }
    }

    public static var native: Theme { builtIn[0] }
    public static var terminal: Theme { builtIn[1] }

    /// Where user themes will be read from.
    public static var userDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "topophany-bar/Themes", directoryHint: .isDirectory)
    }

    /// Off in this release.
    public static let userThemesEnabled = false

    public private(set) var themes: [Theme]
    /// Files that were refused, and why.
    public private(set) var refused: [(file: String, error: LoadError)] = []

    public init(themes: [Theme] = ThemeStore.builtIn) { self.themes = themes }

    /// A theme by ID, or Native.
    public func theme(_ id: String) -> Theme {
        themes.first { $0.id == id } ?? ThemeStore.native
    }

    /// Decodes and validates one theme file.
    public static func load(_ data: Data) -> Result<Theme, LoadError> {
        let theme: Theme
        do {
            theme = try JSONDecoder().decode(Theme.self, from: data)
        } catch {
            return .failure(.unreadable(String(describing: error)))
        }
        let problems = ThemeValidator.refusals(theme)
        return problems.isEmpty ? .success(theme) : .failure(.refused(problems))
    }

    /// Reads `*.json` from `directory`, keeping the valid ones after the
    /// built-ins. Does nothing while user themes are off.
    public mutating func loadUserThemes(from directory: URL = ThemeStore.userDirectory,
                                        enabled: Bool = ThemeStore.userThemesEnabled) {
        guard enabled else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file) else {
                refused.append((file.lastPathComponent, .unreadable("no access")))
                continue
            }
            switch Self.load(data) {
            case .success(let t) where !themes.contains(where: { $0.id == t.id }):
                themes.append(t)
            case .success(let t):
                refused.append((file.lastPathComponent, .unreadable("the ID \(t.id) is taken")))
            case .failure(let e):
                refused.append((file.lastPathComponent, e))
            }
        }
    }
}
