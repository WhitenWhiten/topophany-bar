import SwiftUI

/// Topophany's mark: the app icon's globe in 16 cells of ordered dither,
/// ink on a paper disc in light, its light alone in dark. Each cell's edges
/// fall on whole pixels, so the dither stays crisp at any size.
public struct BrandMark: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    public init() {}

    public var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height), scale = displayScale
            let x0 = (size.width - side) / 2, y0 = (size.height - side) / 2
            func edge(_ k: Int) -> Double { (Double(k) * side / 16 * scale).rounded() / scale }
            func cells(_ rows: [UInt16]) -> Path {
                var path = Path()
                for (y, row) in rows.enumerated() {
                    for x in 0..<16 where row & (0x8000 >> x) != 0 {
                        path.addRect(CGRect(x: x0 + edge(x), y: y0 + edge(y), width: edge(x + 1) - edge(x), height: edge(y + 1) - edge(y)))
                    }
                }
                return path
            }
            if scheme == .dark {
                ctx.fill(cells(Self.night), with: .color(Color(rgb: 0xF4F2EC)))
            } else {
                ctx.fill(cells(Self.disc), with: .color(.white))
                ctx.fill(cells(Self.day), with: .color(Color(rgb: 0x1A1A1A)))
            }
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
