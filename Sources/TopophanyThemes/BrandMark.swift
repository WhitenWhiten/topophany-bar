import SwiftUI

/// Topophany's mark: a dot-matrix globe crossed by one route. Vectors, so
/// it is crisp at any size.
public struct BrandMark: View {
    public init() {}

    public var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 64
            ctx.translateBy(x: (size.width - 64 * k) / 2, y: (size.height - 64 * k) / 2)
            ctx.scaleBy(x: k, y: k)
            let disc = Path(ellipseIn: CGRect(x: 1.5, y: 1.5, width: 61, height: 61))
            ctx.fill(disc, with: .radialGradient(
                Gradient(stops: [.init(color: Color(rgb: 0x2F7EA3), location: 0), .init(color: Color(rgb: 0x15405A), location: 0.5),
                                 .init(color: Color(rgb: 0x0B1A24), location: 1)]),
                center: CGPoint(x: 1.5 + 61 * 0.36, y: 1.5 + 61 * 0.32), startRadius: 0, endRadius: 61 * 0.78))
            for (x, y, r, c) in Self.dots {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Color(rgb: c)))
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: 1.9, y: 1.9, width: 60.2, height: 60.2)),
                       with: .color(Color(rgb: 0x7DD3FC).opacity(0.5)), lineWidth: 1.1)
            var arc = Path()
            arc.move(to: CGPoint(x: 23.72, y: 25.61))
            arc.addQuadCurve(to: CGPoint(x: 57.11, y: 26.14), control: CGPoint(x: 40.61, y: 13.85))
            ctx.stroke(arc, with: .color(Color(rgb: 0x5EEAD4).opacity(0.38)), style: StrokeStyle(lineWidth: 6.72, lineCap: .round))
            ctx.stroke(arc, with: .color(Color(rgb: 0xE6FFFB)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            func dot(_ x: Double, _ y: Double, _ r: Double, _ c: Color) {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(c))
            }
            dot(23.72, 25.61, 3.6, Color(rgb: 0x0A1016))
            dot(23.72, 25.61, 2.6, Color(rgb: 0xFCD34D))
            dot(57.11, 26.14, 6.4, Color(rgb: 0xFCD34D).opacity(0.22))
            dot(57.11, 26.14, 3.4, Color(rgb: 0xFCD34D))
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255, opacity: opacity)
    }
}
