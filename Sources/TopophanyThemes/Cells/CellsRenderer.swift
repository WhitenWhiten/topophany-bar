import SwiftUI
import TopophanySections

/// `cells`: the Terminal look, the TUI's boxed panels on a cell grid.
public struct CellsRenderer: Renderer {
    public init() {}

    public var id: RendererID { .cells }

    public func panel(_ model: PanelModel, context: RenderContext) -> AnyView {
        AnyView(CellsPanel(model: model, ctx: context))
    }

    public func statusItem(_ model: StatusItemModel, context: StatusItemContext) -> AnyView {
        AnyView(CellsStatusItem(model: model, ctx: context))
    }

    public func widget(_ model: WidgetModel, size: WidgetSize, context: RenderContext) -> AnyView {
        AnyView(CellsWidget(model: model, size: size, ctx: context))
    }

    public func widgetBackground(context: RenderContext) -> AnyView {
        AnyView(Rectangle().fill(Color(CellsPalette(context.theme).ink)))
    }

    public var panelCornerRadius: Double { CellsPanel.radius }
}
