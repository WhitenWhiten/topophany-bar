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

    /// Glass tinted the green-blue of a northern sky, a violet second
    /// accent; light or dark, as the system is.
    public static let auroraJSON = #"""
    {"schema": 1, "id": "aurora", "name": "Aurora", "renderer": "cards", "appearance": "system",
     "tokens": {},
     "dark": {
       "accent": "#2DD4BF", "accent2": "#A78BFA", "card": "rgba(45, 212, 191, .07)", "cardEdge": "rgba(94, 234, 212, .14)",
       "panelMaterial": "rgba(12, 28, 34, .62)", "fill": "rgba(94, 234, 212, .2)", "fill2": "rgba(94, 234, 212, .09)"},
     "light": {
       "accent": "#0D9488", "accent2": "#7C3AED", "card": "rgba(240, 253, 250, .7)", "cardEdge": "rgba(13, 148, 136, .14)",
       "panelMaterial": "rgba(236, 253, 248, .62)", "fill": "rgba(13, 148, 136, .18)", "fill2": "rgba(13, 148, 136, .08)"},
     "font": {"family": "SF Pro", "size": 13}}
    """#

    /// Matte, warm cards set in New York, an ink-blue accent; light or
    /// dark, as the system is.
    public static let linenJSON = #"""
    {"schema": 1, "id": "linen", "name": "Linen", "renderer": "cards", "appearance": "system",
     "tokens": {},
     "dark": {
       "accent": "#9DB0E8", "accent2": "#BCA7DE", "card": "rgba(255, 236, 212, .065)", "cardEdge": "rgba(255, 230, 200, .1)",
       "panelMaterial": "rgba(42, 35, 28, .86)", "fill": "rgba(222, 200, 170, .24)", "fill2": "rgba(222, 200, 170, .11)"},
     "light": {
       "accent": "#34509A", "accent2": "#7A5BA8", "card": "rgba(255, 253, 248, .84)", "cardEdge": "rgba(110, 88, 60, .13)",
       "panelMaterial": "rgba(241, 237, 229, .88)", "fill": "rgba(120, 100, 74, .2)", "fill2": "rgba(120, 100, 74, .09)"},
     "font": {"family": "New York", "size": 13}}
    """#

    /// The TUI printed on warm paper.
    public static let paperJSON = #"""
    {"schema": 1, "id": "paper", "name": "Paper", "renderer": "cells", "appearance": "light",
     "tokens": {
       "ink": "#F5F0E6", "inkHigh": "#ECE5D7", "selection": "#E4DDCC", "key": "#E3DBCA", "line": "#D3C9B5", "track": "#E6DFD0",
       "text": "#2A2925", "muted": "#6E695D", "faint": "#A29C8E", "glow": "#FFFFFF", "accent": "#0F766E", "accent2": "#1D4ED8",
       "kind": "#BE185D", "up": "#15803D", "warning": "#B8720A", "down": "#B91C1C", "unknown": "#87929B"},
     "font": {"family": "SF Mono", "size": 12}}
    """#

    /// The TUI at nightfall: pastels on deep indigo.
    public static let duskJSON = #"""
    {"schema": 1, "id": "dusk", "name": "Dusk", "renderer": "cells", "appearance": "dark",
     "tokens": {
       "ink": "#1A1735", "inkHigh": "#201C3F", "selection": "#2E2959", "key": "#2A2650", "line": "#3D3869", "track": "#252147",
       "text": "#E6E2F8", "muted": "#A49ECB", "faint": "#68629A", "glow": "#FFF4FA", "accent": "#B4A7FA", "accent2": "#8BD3F7",
       "kind": "#F4A7C9", "up": "#6EE7B0", "warning": "#F7B96B", "down": "#F7768E", "unknown": "#7A759F"},
     "font": {"family": "SF Mono", "size": 12}}
    """#

    /// Every built-in theme, through the same path a file takes: the cards
    /// themes, then the cells themes.
    public static let builtIn: [Theme] = [nativeJSON, auroraJSON, linenJSON, terminalJSON, paperJSON, duskJSON].map { json in
        switch load(Data(json.utf8)) {
        case .success(let t): return t
        case .failure(let e): fatalError("built-in theme refused: \(e)")
        }
    }

    public static var native: Theme { builtIn[0] }
    public static var aurora: Theme { builtIn[1] }
    public static var linen: Theme { builtIn[2] }
    public static var terminal: Theme { builtIn[3] }
    public static var paper: Theme { builtIn[4] }
    public static var dusk: Theme { builtIn[5] }

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
