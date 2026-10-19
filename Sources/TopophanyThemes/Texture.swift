import CoreGraphics
import SwiftUI

/// A surface's fine texture, in one ink: woven threads, or paper's grain.
/// Light enough to read as a material, never as a pattern, and the same
/// tile everywhere it is drawn.
enum Texture: String, Sendable, CaseIterable {
    case none, weave, grain

    init(_ name: String) { self = Texture(rawValue: name) ?? .none }

    /// 64 points square at 2x, white on clear: the view lends it its ink.
    static let tiles: [Texture: CGImage] = {
        var out: [Texture: CGImage] = [:]
        for t in [Texture.weave, .grain] { out[t] = t.draw(side: 128) }
        return out
    }()

    /// The same threads and specks at every launch: a seeded generator.
    struct Seeded {
        var state: UInt64

        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    func draw(side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var r = Seeded(state: self == .weave ? 7 : 11)
        let s = Double(side)
        func fill(_ rect: CGRect, _ alpha: Double) {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
            ctx.fill(rect)
        }
        switch self {
        case .none:
            break
        case .weave:
            // Warp and weft a pixel wide, two apart, each thread its own
            // weight; where they cross, a little more, as a thread rises.
            var x = 0.0
            while x < s {
                fill(CGRect(x: x, y: 0, width: 1, height: s), 0.28 + 0.4 * r.next())
                x += 2
            }
            var y = 0.0
            while y < s {
                fill(CGRect(x: 0, y: y, width: s, height: 1), 0.28 + 0.4 * r.next())
                y += 2
            }
            for _ in 0..<(side * side / 40) {
                let px = (r.next() * s / 2).rounded(.down) * 2, py = (r.next() * s / 2).rounded(.down) * 2
                fill(CGRect(x: px, y: py, width: 1, height: 1), 0.6 * r.next())
            }
        case .grain:
            // Specks of every weight, and now and then a fibre.
            for _ in 0..<(side * side / 5) {
                let px = (r.next() * s).rounded(.down), py = (r.next() * s).rounded(.down)
                fill(CGRect(x: px, y: py, width: 1, height: 1), 0.15 + 0.85 * r.next() * r.next())
            }
            for _ in 0..<6 {
                let px = r.next() * s, py = r.next() * s, len = 3 + 5 * r.next()
                let horizontal = r.next() < 0.5
                fill(CGRect(x: px, y: py, width: horizontal ? len : 1, height: horizontal ? 1 : len), 0.45)
            }
        }
        return ctx.makeImage()
    }
}

/// A texture over what's beneath it, in `color`.
struct TextureFill: View {
    var texture: Texture
    var color: Color

    var body: some View {
        if let tile = Texture.tiles[texture] {
            Rectangle().fill(color)
                .mask { Rectangle().fill(ImagePaint(image: Image(decorative: tile, scale: 2), scale: 1)) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
