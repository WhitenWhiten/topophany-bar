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

    public func statusItem(_ model: StatusItemModel, context: StatusItemContext) -> AnyView {
        AnyView(CardsStatusItem(model: model, ctx: context))
    }

    public func widget(_ model: WidgetModel, size: WidgetSize, context: RenderContext) -> AnyView {
        AnyView(CardsWidget(model: model, size: size, ctx: context))
    }

    public func widgetBackground(context: RenderContext) -> AnyView {
        AnyView(CardsWidgetBackground(ctx: context))
    }
}

/// The menu bar item: a globe with the status badge cut into its corner,
/// and the count or words beside it.
struct CardsStatusItem: View {
    var model: StatusItemModel
    var ctx: StatusItemContext

    var ink: Color { ctx.template ? .black : (ctx.menuBarIsDark ? .white : Color(white: 0.08)) }

    var badge: Color {
        guard model.statusColors, !ctx.template else { return ink }
        switch model.mark {
        case .up: return ctx.menuBarIsDark ? Color(rgb: 0x32D74B) : Color(rgb: 0x28B449)
        case .degraded: return ctx.menuBarIsDark ? Color(rgb: 0xFF9F0A) : Color(rgb: 0xF08C00)
        case .down: return ctx.menuBarIsDark ? Color(rgb: 0xFF453A) : Color(rgb: 0xFF3B30)
        case .unknown, .offline: return ink
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Canvas { c, size in
                draw(&c, size)
            }
            .frame(width: 19, height: 19)
            if !model.text.isEmpty {
                Text(model.text)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .tracking(-0.13)
                    .foregroundStyle(ink)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 1)
        .frame(height: 22)
    }

    func draw(_ c: inout GraphicsContext, _ size: CGSize) {
        // The globe, with room cut out for the badge.
        var globe = c
        globe.clipToLayer { mask in
            mask.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            mask.blendMode = .clear
            mask.fill(Path(ellipseIn: CGRect(x: 14.6 - 5.1, y: 14.6 - 5.1, width: 10.2, height: 10.2)), with: .color(.white))
        }
        var g = Path()
        g.addEllipse(in: CGRect(x: 2, y: 2, width: 14, height: 14))
        g.addEllipse(in: CGRect(x: 6, y: 2, width: 6, height: 14))
        g.move(to: CGPoint(x: 2, y: 9))
        g.addLine(to: CGPoint(x: 16, y: 9))
        globe.stroke(g, with: .color(ink), style: StrokeStyle(lineWidth: 1.45, lineCap: .round))

        let b = badge
        switch model.mark {
        case .up:
            c.fill(Path(ellipseIn: CGRect(x: 11.3, y: 11.3, width: 6.6, height: 6.6)), with: .color(b))
        case .degraded:
            var t = Path()
            t.move(to: CGPoint(x: 14.6, y: 10.9))
            t.addLine(to: CGPoint(x: 18.3, y: 17.4))
            t.addLine(to: CGPoint(x: 10.9, y: 17.4))
            t.closeSubpath()
            c.fill(t, with: .color(b))
            c.stroke(t, with: .color(b), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
        case .down:
            var x = c
            x.clipToLayer { mask in
                mask.fill(Path(roundedRect: CGRect(x: 11.1, y: 11.1, width: 7, height: 7), cornerRadius: 1.6), with: .color(.white))
                mask.blendMode = .clear
                var cross = Path()
                cross.move(to: CGPoint(x: 13.1, y: 13.1))
                cross.addLine(to: CGPoint(x: 16.1, y: 16.1))
                cross.move(to: CGPoint(x: 16.1, y: 13.1))
                cross.addLine(to: CGPoint(x: 13.1, y: 16.1))
                mask.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: 1.15, lineCap: .round))
            }
            x.fill(Path(CGRect(x: 10, y: 10, width: 9, height: 9)), with: .color(b))
        case .unknown:
            c.stroke(Path(ellipseIn: CGRect(x: 11.9, y: 11.9, width: 5.4, height: 5.4)), with: .color(b), lineWidth: 1.3)
        case .offline:
            c.stroke(Path(ellipseIn: CGRect(x: 11.9, y: 11.9, width: 5.4, height: 5.4)), with: .color(b),
                     style: StrokeStyle(lineWidth: 1.3, dash: [1.4, 1.2]))
        }
    }
}
