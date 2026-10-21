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
    /// How many times the keyboard has asked the panel to leap, as its
    /// quick scroll does. Each new one leaps once.
    public var leaps = 0
    /// Ages count up on their own, as a widget's must between reloads.
    /// Off for snapshots, which draw ages as of the model's `now`.
    public var liveDates = false

    public init(theme: Theme, colorScheme: ColorScheme = .dark, backdrop: Backdrop = .flat,
                textSize: TopophanyKit.Settings.Appearance.TextSize = .default, focus: String? = nil, reduceTransparency: Bool = false,
                increaseContrast: Bool = false, widgetRendering: WidgetRendering = .fullColor, maxHeight: Double? = nil,
                leaps: Int = 0) {
        self.theme = theme
        self.colorScheme = colorScheme
        self.backdrop = backdrop
        self.textSize = textSize
        self.focus = focus
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.widgetRendering = widgetRendering
        self.maxHeight = maxHeight
        self.leaps = leaps
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

/// The menu bar item in its two parts, which the app draws apart: this
/// Mac's readings change once a sample, the rest whenever it moves.
public struct StatusItemParts {
    /// This Mac's readings, before the rest; `nil` when none are shown.
    public var readings: AnyView?
    /// Between the readings and the rest.
    public var spacing: Double
    /// The verdict: the mark and its count or words.
    public var item: AnyView

    public init(readings: AnyView?, spacing: Double, item: AnyView) {
        self.readings = readings
        self.spacing = spacing
        self.item = item
    }
}

/// What the panel's controls do; supplied by the app shell.
public struct PanelActions: @unchecked Sendable {
    public var openTerminal: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void
    public var quit: @MainActor () -> Void
    public var openAttention: @MainActor (AttentionSection.Item?) -> Void
    public var focus: @MainActor (String?) -> Void
    /// Quiets the menu bar's alert until it gets worse, or shows it again:
    /// whichever the alert is ready for when it's called.
    public var toggleQuiet: @MainActor () -> Void
    /// Downloads `topo`, while none can run.
    public var download: @MainActor (TopoBuild) -> Void

    public init(openTerminal: @escaping @MainActor () -> Void = {}, openSettings: @escaping @MainActor () -> Void = {},
                quit: @escaping @MainActor () -> Void = {},
                openAttention: @escaping @MainActor (AttentionSection.Item?) -> Void = { _ in },
                focus: @escaping @MainActor (String?) -> Void = { _ in },
                toggleQuiet: @escaping @MainActor () -> Void = {},
                download: @escaping @MainActor (TopoBuild) -> Void = { _ in }) {
        self.openTerminal = openTerminal
        self.openSettings = openSettings
        self.quit = quit
        self.openAttention = openAttention
        self.focus = focus
        self.toggleQuiet = toggleQuiet
        self.download = download
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
    /// The menu bar item, whole.
    func statusItem(_ model: StatusItemModel, context: StatusItemContext) -> AnyView
    /// The menu bar item in its parts, to draw each only when it changes.
    func statusItemParts(_ model: StatusItemModel, context: StatusItemContext) -> StatusItemParts
    /// A widget in `size`'s layout, filling `bounds`: the points WidgetKit
    /// gives it, which vary with the display.
    func widget(_ model: WidgetModel, size: WidgetSize, bounds: CGSize, context: RenderContext) -> AnyView
    /// What a widget sits on: WidgetKit's container background.
    func widgetBackground(context: RenderContext) -> AnyView
    /// The panel's corner radius in `theme`: its window is masked to it, so
    /// the window's shadow follows the corners.
    func panelCornerRadius(_ theme: Theme) -> Double
    /// The theme's colors, as this renderer resolves its slots.
    func colors(context: RenderContext) -> ThemeColors
}

/// A theme's colors, for choosing one: what its panel sits on, its edge,
/// and its two accents and four status colors.
public struct ThemeColors {
    /// Layers, from the bottom.
    public var ground: [Color]
    public var edge: Color
    /// Accent, second accent, then up, warning, down and unknown.
    public var swatches: [Color]
}

/// A theme as a chip of its colors: its ground, and a dot for each
/// swatch.
public struct ThemeSwatch: View {
    var theme: Theme
    var colorScheme: ColorScheme

    public init(theme: Theme, colorScheme: ColorScheme) {
        self.theme = theme
        self.colorScheme = colorScheme
    }

    public var body: some View {
        let c = Renderers.renderer(for: theme).colors(context: RenderContext(theme: theme, colorScheme: colorScheme))
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            ForEach(Array(c.ground.enumerated()), id: \.offset) { _, g in shape.fill(g) }
            HStack(spacing: 3.5) {
                ForEach(Array(c.swatches.enumerated()), id: \.offset) { _, s in Circle().fill(s).frame(width: 7, height: 7) }
            }
        }
        .overlay(shape.strokeBorder(c.edge, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

extension Renderer {
    public func statusItem(_ model: StatusItemModel, context: StatusItemContext) -> AnyView {
        let parts = statusItemParts(model, context: context)
        return AnyView(HStack(spacing: parts.spacing) {
            if let r = parts.readings { r }
            parts.item
        })
    }
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
            case .map: ids.append("map")
            case .applications(let a): ids += a.rows.map { "app:" + $0.id }
            case .services(let cards): ids += cards.map { "service:" + $0.id }
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
