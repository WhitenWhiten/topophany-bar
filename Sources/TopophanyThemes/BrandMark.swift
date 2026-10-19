import SwiftUI

/// Topophany's mark: a dot-matrix globe lit from the upper left, crossed by
/// one route. Vectors, so it is crisp at any size.
public struct BrandMark: View {
    public init() {}

    public var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 64
            ctx.translateBy(x: (size.width - 64 * k) / 2, y: (size.height - 64 * k) / 2)
            ctx.scaleBy(x: k, y: k)
            for layer in Self.under { layer.draw(in: ctx) }
            for (x, y, r, c) in Self.dots {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Color(rgb: c)))
            }
            for layer in Self.over { layer.draw(in: ctx) }
        }
        .accessibilityHidden(true)
    }
}

extension BrandMark {
    enum Shape: Sendable {
        case circle(Double, Double, Double)
        /// A band: its outline as x and y in turn, and a circle at each end.
        case ribbon([Double], ends: [(Double, Double, Double)])

        var path: Path {
            switch self {
            case .circle(let x, let y, let r):
                return Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            case .ribbon(let outline, let ends):
                var band = Path()
                band.addLines(stride(from: 0, to: outline.count, by: 2).map { CGPoint(x: outline[$0], y: outline[$0 + 1]) })
                band.closeSubpath()
                return ends.reduce(band) { $0.union(Shape.circle($1.0, $1.1, $1.2).path) }
            }
        }
    }

    /// Gradient stops are offset, 0xRRGGBB and opacity.
    enum Paint: Sendable {
        case color(UInt32, Double)
        case linear(CGPoint, CGPoint, [(Double, UInt32, Double)])
        case radial(CGPoint, Double, [(Double, UInt32, Double)])

        var shading: GraphicsContext.Shading {
            func gradient(_ stops: [(Double, UInt32, Double)]) -> Gradient {
                Gradient(stops: stops.map { .init(color: Color(rgb: $0.1, opacity: $0.2), location: $0.0) })
            }
            switch self {
            case .color(let c, let opacity): return .color(Color(rgb: c, opacity: opacity))
            case .linear(let from, let to, let stops): return .linearGradient(gradient(stops), startPoint: from, endPoint: to)
            case .radial(let centre, let r, let stops):
                return .radialGradient(gradient(stops), center: centre, startRadius: 0, endRadius: r)
            }
        }
    }

    /// One shape of the mark, filled, or stroked when it has a width.
    struct Layer: Sendable {
        var shape: Shape
        var paint: Paint
        var stroke: Double?
        var clip: Shape?

        init(_ shape: Shape, _ paint: Paint, stroke: Double? = nil, clip: Shape? = nil) {
            (self.shape, self.paint, self.stroke, self.clip) = (shape, paint, stroke, clip)
        }

        func draw(in context: GraphicsContext) {
            var ctx = context
            if let clip { ctx.clip(to: clip.path) }
            if let stroke {
                ctx.stroke(shape.path, with: paint.shading, lineWidth: stroke)
            } else {
                ctx.fill(shape.path, with: paint.shading)
            }
        }
    }
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255, opacity: opacity)
    }
}
