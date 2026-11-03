import SwiftUI
import TopophanySections

/// `glance`: Native's glass, type and colors, laid out to be read at a
/// glance (DESIGN.md §8). Status and Seen from are one card; a section
/// that needs a look stays open, a calm one folds into a line that opens on
/// a click; the map, Fleet and Time zones share one card, a lens each; and
/// pinned items are tiles. The menu bar item is Native's, and so is every
/// widget but Status, which reads its checks off a dial.
public struct GlanceRenderer: Renderer {
    public init() {}

    public var id: RendererID { .glance }

    public func panel(_ model: PanelModel, context: RenderContext) -> AnyView {
        AnyView(GlancePanel(model: model, ctx: context))
    }

    public func statusItemParts(_ model: StatusItemModel, context: StatusItemContext) -> StatusItemParts {
        CardsRenderer().statusItemParts(model, context: context)
    }

    public func widget(_ model: WidgetModel, size: WidgetSize, bounds: CGSize, context: RenderContext) -> AnyView {
        AnyView(SnapshotWidget(model: model, bounds: bounds, context: context, ink: CardsPalette.resolve(context).l2) { room in
            // Sources have no checks to set on a dial: their widget is
            // Native's, as is every other kind.
            if model.kind == .status, model.status.sources == nil {
                GlanceWidget(model: model, size: size, bounds: room, ctx: context)
            } else {
                CardsWidget(model: model, size: size, bounds: room, ctx: context)
            }
        })
    }

    public func widgetBackground(context: RenderContext) -> AnyView {
        CardsRenderer().widgetBackground(context: context)
    }

    public func panelCornerRadius(_ theme: Theme) -> Double { CardsStyle(theme).panelRadius }

    public func colors(context: RenderContext) -> ThemeColors {
        CardsRenderer().colors(context: context)
    }

    /// The hero's observers first, then each part as Glance lays it out.
    public func focusOrder(_ model: PanelModel) -> [String] { GlanceLayout(model).focusOrder }
}
