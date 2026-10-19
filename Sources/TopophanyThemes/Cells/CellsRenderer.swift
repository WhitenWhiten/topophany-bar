import SwiftUI
import TopophanySections

/// `cells`: the Terminal look, the TUI's boxed panels on a cell grid.
public struct CellsRenderer: Renderer {
    public init() {}

    public var id: RendererID { .cells }

    public func panel(_ model: PanelModel, context: RenderContext) -> AnyView {
        AnyView(CellsPanel(model: model, ctx: context))
    }

    public func statusItemParts(_ model: StatusItemModel, context: StatusItemContext) -> StatusItemParts {
        let readings = model.readings.isEmpty ? nil : AnyView(CellsReadingsChip(readings: model.readings, ctx: context))
        return StatusItemParts(readings: readings, spacing: 4, item: AnyView(CellsStatusItem(model: model, ctx: context)))
    }

    public func widget(_ model: WidgetModel, size: WidgetSize, bounds: CGSize, context: RenderContext) -> AnyView {
        AnyView(CellsWidget(model: model, size: size, bounds: bounds, ctx: context))
    }

    public func widgetBackground(context: RenderContext) -> AnyView {
        AnyView(Rectangle().fill(Color(CellsPalette(context.theme).ink)))
    }

    public var panelCornerRadius: Double { CellsPanel.radius }
}
