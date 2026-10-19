import SwiftUI

/// How the cards renderer draws beyond its colors, from a theme's style
/// slots (`StyleSlots.cards`).
struct CardsStyle {
    enum Surface: String { case glass, matte, night }

    var surface = Surface.glass
    var meter = MeterStyle.ticks
    /// Section titles in letterspaced capitals, without their symbols.
    var caps = false
    var texture = Texture.none

    init() {}

    init(_ theme: Theme) {
        surface = Surface(rawValue: theme.style("surface")) ?? .glass
        meter = MeterStyle(rawValue: theme.style("meter")) ?? .ticks
        caps = theme.style("titles") == "caps"
        texture = Texture(theme.style("texture"))
    }

    /// The panel's corners: a ruled page has crisp ones.
    var panelRadius: Double { surface == .matte ? 10 : 18 }
    /// A card's, and what follows from it: tiles, chips, the hero.
    var cardRadius: Double { surface == .matte ? 4 : 13 }
    /// A row's or a tile's corners, at `r` on glass: crisp on matte, softer
    /// at night.
    func radius(_ r: Double) -> Double {
        switch surface {
        case .glass: r
        case .matte: min(r, 3)
        case .night: r + 3
        }
    }

    /// A chip's or a pill's corners, at `r` on glass: at night, round at
    /// the ends.
    func chip(_ r: Double) -> Double { surface == .night ? 100 : radius(r) }

    /// The verdict's tile, `size` wide: a squircle, a crisp square on matte,
    /// a disc at night.
    func heroRadius(_ size: Double) -> Double {
        switch surface {
        case .glass: size * 12 / 44
        case .matte: size * 5 / 44
        case .night: size / 2
        }
    }
}

/// A reading along a meter, or parts of a whole, against its track.
enum MeterStyle: String {
    /// Fine graduated ticks, each lit or not.
    case ticks
    /// A scale: a rule with its graduations, and the reading a thin bar
    /// upon it.
    case rule
    /// A matrix of dots.
    case dots

    struct Part {
        /// Where it ends along the meter, 0 … 1; it starts where the one
        /// before it ends.
        var end: Double
        var color: Color
    }

    /// How far a limit's mark reaches past the meter, above and below.
    static let overhang = 2.5

    /// Draws `parts` in a meter `size` tall at the context's origin; the
    /// context reaches `overhang` above and below for the limit's mark.
    func draw(_ ctx: GraphicsContext, size s: CGSize, parts: [Part], track: Color, limit: Double?, ink: Color, scale: Color) {
        func color(at f: Double) -> Color? { parts.first { f < $0.end }?.color }
        switch self {
        case .ticks:
            let tick = 1.3, gap = 1.25
            let n = max(1, Int((s.width + gap) / (tick + gap)))
            let pitch = (s.width + gap) / Double(n)
            let w = pitch - gap
            for i in 0..<n {
                let f = (Double(i) + 0.5) / Double(n)
                let r = CGRect(x: Double(i) * pitch, y: 0, width: w, height: s.height)
                ctx.fill(Path(roundedRect: r, cornerRadius: min(0.6, w / 2)), with: .color(color(at: f) ?? track))
            }
            if let l = limit, l < 100 {
                let x = s.width * l / 100
                ctx.fill(Path(roundedRect: CGRect(x: x - 0.75, y: -2, width: 1.5, height: s.height + 4), cornerRadius: 0.75), with: .color(ink))
            }
        case .rule:
            let base = s.height - 0.5
            ctx.fill(Path(CGRect(x: 0, y: base - 0.375, width: s.width, height: 0.75)), with: .color(scale))
            for k in 0...10 {
                let x = min(s.width - 0.75, s.width * Double(k) / 10)
                let h = k % 5 == 0 ? 3.0 : 1.75
                ctx.fill(Path(CGRect(x: x, y: base - h, width: 0.75, height: h)), with: .color(scale))
            }
            let bar = max(2, (s.height - 1) * 0.55)
            var x = 0.0
            for p in parts where p.end > x {
                ctx.fill(Path(CGRect(x: s.width * x, y: base - 0.375 - bar, width: s.width * (p.end - x), height: bar)),
                         with: .color(p.color))
                x = p.end
            }
            if let l = limit, l < 100 {
                let lx = s.width * l / 100
                var t = Path()
                t.move(to: CGPoint(x: lx - 2.4, y: -2.2))
                t.addLine(to: CGPoint(x: lx + 2.4, y: -2.2))
                t.addLine(to: CGPoint(x: lx, y: 1.4))
                t.closeSubpath()
                ctx.fill(t, with: .color(ink))
                ctx.fill(Path(CGRect(x: lx - 0.375, y: 1.4, width: 0.75, height: base - 1.4)), with: .color(ink.opacity(0.6)))
            }
        case .dots:
            let rows = s.height >= 4.5 ? 2 : 1
            let gap = 0.9
            let d = min(1.9, (s.height - gap * Double(rows - 1)) / Double(rows))
            let n = max(1, Int((s.width + gap) / (d + gap)))
            let pitch = (s.width - d) / Double(max(1, n - 1))
            let top = (s.height - (Double(rows) * d + Double(rows - 1) * gap)) / 2
            for i in 0..<n {
                let f = (Double(i) + 0.5) / Double(n)
                let c = color(at: f) ?? track
                for row in 0..<rows {
                    let r = CGRect(x: Double(i) * pitch, y: top + Double(row) * (d + gap), width: d, height: d)
                    ctx.fill(Path(ellipseIn: r), with: .color(c))
                }
            }
            if let l = limit, l < 100 {
                let x = s.width * l / 100
                ctx.fill(Path(roundedRect: CGRect(x: x - 0.5, y: -2, width: 1, height: s.height + 4), cornerRadius: 0.5), with: .color(ink))
            }
        }
    }

    /// What is unknown: never empty, never zero.
    func drawUnknown(_ ctx: GraphicsContext, size s: CGSize, color: Color) {
        switch self {
        case .ticks, .dots:
            var hatch = ctx
            hatch.clip(to: Path(roundedRect: CGRect(origin: .zero, size: s), cornerRadius: s.height / 2))
            var p = Path()
            var x = -s.height
            while x < s.width + s.height {
                p.move(to: CGPoint(x: x, y: s.height))
                p.addLine(to: CGPoint(x: x + s.height, y: 0))
                x += 6 * 0.7071
            }
            hatch.stroke(p, with: .color(color), lineWidth: 2.2)
        case .rule:
            var base = Path()
            base.move(to: CGPoint(x: 0, y: s.height - 0.5))
            base.addLine(to: CGPoint(x: s.width, y: s.height - 0.5))
            ctx.stroke(base, with: .color(color), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
        }
    }

    /// A history of readings as bars, newest at the right: lit columns of
    /// ticks, hairlines on a scale, or columns of dots.
    func drawHistory(_ ctx: GraphicsContext, size s: CGSize, values: [Double], top: Double, capacity: Int, color: Color, baseline: Color) {
        let n = max(capacity, values.count)
        guard n > 0 else { return }
        ctx.fill(Path(CGRect(x: 0, y: s.height - (self == .rule ? 0.75 : 1), width: s.width, height: self == .rule ? 0.75 : 1)),
                 with: .color(baseline))
        let pitch = s.width / Double(n)
        let shown = Array(values.suffix(n).reversed().enumerated())
        switch self {
        case .ticks:
            let w = max(0.8, pitch - min(1, pitch * 0.3))
            var path = Path()
            for (i, v) in shown {
                let h = max(1, min(1, v / max(top, 1e-9)) * s.height)
                path.addRect(CGRect(x: s.width - Double(i + 1) * pitch + (pitch - w), y: s.height - h, width: w, height: h))
            }
            ctx.fill(path, with: .color(color))
        case .rule:
            var path = Path()
            for (i, v) in shown {
                let h = max(1, min(1, v / max(top, 1e-9)) * (s.height - 0.75))
                path.addRect(CGRect(x: s.width - Double(i + 1) * pitch + pitch / 2 - 0.4, y: s.height - 0.75 - h, width: 0.8, height: h))
            }
            ctx.fill(path, with: .color(color))
        case .dots:
            let d = min(1.6, pitch - 0.6)
            let step = d + 0.75
            let rows = Int((s.height - 1.5) / step)
            var path = Path()
            for (i, v) in shown {
                let k = max(1, Int((min(1, v / max(top, 1e-9)) * Double(rows)).rounded()))
                let x = s.width - Double(i + 1) * pitch + (pitch - d) / 2
                for row in 0..<k {
                    path.addEllipse(in: CGRect(x: x, y: s.height - 1.75 - Double(row + 1) * step + 0.75, width: d, height: d))
                }
            }
            ctx.fill(path, with: .color(color))
        }
    }
}
