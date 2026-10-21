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
        let item = HStack(spacing: 4) {
            if context.drawsPortrait, let portrait = model.portrait(in: context) {
                MenuBarPortrait(animation: portrait, height: Double(model.iconSize), speed: model.iconSpeed,
                                motion: model.activity == .live ? context.motion : .still)
            }
            CellsStatusItem(model: model, ctx: context)
        }
        return StatusItemParts(readings: readings, spacing: 4, item: AnyView(item))
    }

    public func widget(_ model: WidgetModel, size: WidgetSize, bounds: CGSize, context: RenderContext) -> AnyView {
        AnyView(CellsWidget(model: model, size: size, bounds: bounds, ctx: context))
    }

    public func widgetBackground(context: RenderContext) -> AnyView {
        let p = CellsPalette(context.theme)
        return AnyView(ZStack {
            Rectangle().fill(Color(p.ink))
            TextureFill(texture: p.texture, color: Color(p.grain))
        })
    }

    public func panelCornerRadius(_ theme: Theme) -> Double { CellsPanel.radius }

    /// The ink inside a box's line.
    public func colors(context: RenderContext) -> ThemeColors {
        let p = CellsPalette(context.theme)
        return ThemeColors(ground: [Color(p.ink)], edge: Color(p.line),
                           swatches: [p.accent, p.accent2, p.up, p.warn, p.down, p.unknown].map { Color($0) })
    }
}
