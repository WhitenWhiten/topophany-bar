import SwiftUI
import TopophanyKit
import TopophanySections

/// How a surface is drawn: the theme, light or dark, and what the system
/// asks for.
public struct RenderContext: Sendable {
    public enum Backdrop: Sendable, Hashable {
        /// On screen: real materials behind the panel.
        case live
        /// Off screen (snapshots, thumbnails, widgets): drawn fills.
        case flat
    }

    /// WidgetKit's rendering modes. In `vibrant`, macOS drops a desktop
    /// widget's background and color while another app is in front.
    public enum WidgetRendering: Sendable, Hashable { case fullColor, accented, vibrant }

    public var theme: Theme
    public var colorScheme: ColorScheme
    public var backdrop: Backdrop
    public var textSize: TopophanyKit.Settings.Appearance.TextSize
    /// The row the keyboard is on, by ID.
    public var focus: String?
    public var reduceTransparency: Bool
    public var increaseContrast: Bool
    public var widgetRendering: WidgetRendering
    /// The tallest the panel may be; Status stays pinned and the rest
    /// scrolls when it would be taller.
    public var maxHeight: Double?
    /// Ages count up on their own, as a widget's must between reloads.
    /// Off for snapshots, which draw ages as of the model's `now`.
    public var liveDates = false

    public init(theme: Theme, colorScheme: ColorScheme = .dark, backdrop: Backdrop = .flat,
                textSize: TopophanyKit.Settings.Appearance.TextSize = .default, focus: String? = nil, reduceTransparency: Bool = false,
                increaseContrast: Bool = false, widgetRendering: WidgetRendering = .fullColor, maxHeight: Double? = nil) {
        self.theme = theme
        self.colorScheme = colorScheme
        self.backdrop = backdrop
        self.textSize = textSize
        self.focus = focus
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.widgetRendering = widgetRendering
        self.maxHeight = maxHeight
    }

    /// The light or dark the theme draws in.
    public var effectiveScheme: ColorScheme {
        switch theme.appearance {
        case .light: .light
        case .dark: .dark
        case .system: colorScheme
        }
    }

    var scale: Double {
        switch textSize {
        case .small: 0.92
        case .default: 1
        case .large: 1.12
        }
    }
}

/// What the menu bar item sits on, and where its motion stands.
public struct StatusItemContext: Sendable {
    public var theme: Theme
    /// The menu bar's own appearance, which may differ from the panel's:
    /// the item takes the ink the menu bar's own items take on it.
    public var menuBarIsDark: Bool
    public var motion: StatusItemMotion

    public init(theme: Theme, menuBarIsDark: Bool, motion: StatusItemMotion = .still) {
        self.theme = theme
        self.menuBarIsDark = menuBarIsDark
        self.motion = motion
    }
}

/// What the panel's controls do; supplied by the app shell.
public struct PanelActions: @unchecked Sendable {
    public var openTerminal: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var quit: @MainActor () -> Void
    public var openAttention: @MainActor (AttentionSection.Item?) -> Void
    public var focus: @MainActor (String?) -> Void

    public init(openTerminal: @escaping @MainActor () -> Void = {}, openSettings: @escaping @MainActor () -> Void = {},
                quit: @escaping @MainActor () -> Void = {},
                openAttention: @escaping @MainActor (AttentionSection.Item?) -> Void = { _ in },
                focus: @escaping @MainActor (String?) -> Void = { _ in }) {
        self.openTerminal = openTerminal
        self.openSettings = openSettings
        self.quit = quit
        self.openAttention = openAttention
        self.focus = focus
    }
}

extension EnvironmentValues {
    @Entry public var panelActions = PanelActions()
}

/// Lays out section models for every surface. A renderer owns the status
/// glyphs and what each token slot means; a theme only fills the slots.
@MainActor
public protocol Renderer {
    var id: RendererID { get }
    func panel(_ model: PanelModel, context: RenderContext) -> AnyView
    func statusItem(_ model: StatusItemModel, context: StatusItemContext) -> AnyView
    /// A widget in `size`'s layout, filling `bounds`: the points WidgetKit
    /// gives it, which vary with the display.
    func widget(_ model: WidgetModel, size: WidgetSize, bounds: CGSize, context: RenderContext) -> AnyView
    /// What a widget sits on: WidgetKit's container background.
    func widgetBackground(context: RenderContext) -> AnyView
    /// The panel's corner radius: its window is masked to it, so the
    /// window's shadow follows the corners.
    var panelCornerRadius: Double { get }
}

@MainActor
public enum Renderers {
    public static func renderer(for id: RendererID) -> any Renderer {
        switch id {
        case .cards: CardsRenderer()
        case .cells: CellsRenderer()
        }
    }

    public static func renderer(for theme: Theme) -> any Renderer { renderer(for: theme.renderer) }

    /// The keyboard's stops in the panel, in order: what ↑ and ↓ move
    /// between and ↵ opens.
    public static func focusOrder(_ model: PanelModel) -> [String] {
        var ids: [String] = []
        for s in model.sections {
            switch s {
            case .attention(let a):
                ids += a.items.map { "attention:" + $0.id }
                if a.more > 0 { ids.append("attention:more") }
            case .seen(let s): ids += (s.problems ?? []).map { "seen:" + $0.id }
            case .applications(let a): ids += a.rows.map { "app:" + $0.id }
            case .servers(let cards): ids += cards.map { "server:" + $0.id }
            case .zones, .fleet: break
            case .mac(.server(let c, _)): ids.append("server:" + c.id)
            case .mac(.local): break
            }
        }
        return ids
    }
}

extension Color {
    init(_ c: RGBA) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }
}
