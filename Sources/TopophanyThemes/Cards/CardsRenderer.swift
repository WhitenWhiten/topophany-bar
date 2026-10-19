import SwiftUI
import TopophanySections

/// `cards`: the Native look. System materials, SF Pro, SF Symbols and
/// system colors, the accent color for capacity.
public struct CardsRenderer: Renderer {
    public init() {}

    public var id: RendererID { .cards }

    public func panel(_ model: PanelModel, context: RenderContext) -> AnyView {
        AnyView(CardsPanel(model: model, ctx: context))
    }

    public func statusItemParts(_ model: StatusItemModel, context: StatusItemContext) -> StatusItemParts {
        let item = CardsStatusItem(model: model, ctx: context)
        let readings = model.readings.isEmpty ? nil : AnyView(CardsMenuReadings(readings: model.readings, ink: item.ink))
        return StatusItemParts(readings: readings, spacing: 9, item: AnyView(item))
    }

    public func widget(_ model: WidgetModel, size: WidgetSize, bounds: CGSize, context: RenderContext) -> AnyView {
        AnyView(CardsWidget(model: model, size: size, bounds: bounds, ctx: context))
    }

    public func widgetBackground(context: RenderContext) -> AnyView {
        AnyView(CardsWidgetBackground(ctx: context))
    }

    public func panelCornerRadius(_ theme: Theme) -> Double { CardsStyle(theme).panelRadius }

    /// The panel's tint and a card's over an opaque stand-in for the glass;
    /// a matte or night ground as it is.
    public func colors(context: RenderContext) -> ThemeColors {
        let p = CardsPalette.resolve(context)
        let ground: [Color] = switch p.style.surface {
        case .glass: [p.isDark ? Color(rgb: 0x1E1E23) : Color(rgb: 0xF4F4F6), p.panel, p.card]
        case .matte: [p.panel]
        case .night: [p.panel2 ?? p.panel, p.panel.opacity(0.55), p.card]
        }
        return ThemeColors(ground: ground,
                           edge: p.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.1),
                           swatches: [p.accent, p.accent2, p.up, p.warn, p.down, p.unknown])
    }
}
