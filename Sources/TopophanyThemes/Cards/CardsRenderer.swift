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

    public var panelCornerRadius: Double { CardsPanel.radius }
}
