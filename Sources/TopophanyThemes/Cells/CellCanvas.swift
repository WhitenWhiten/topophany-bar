import SwiftUI
import TopophanySections

/// The size of one cell: SF Mono's advance (1266/2048 em) by the line.
public struct CellMetrics: Sendable, Hashable {
    public var fontSize: Double
    public var line: Double

    public init(fontSize: Double, line: Double) {
        self.fontSize = fontSize
        self.line = line
    }

    public var cell: Double { fontSize * 1266 / 2048 }

    /// The panel's: 12 pt on 18 pt lines.
    public static let panel = CellMetrics(fontSize: 12, line: 18)
    /// Widgets': 11 pt on 16 pt lines.
    public static let widget = CellMetrics(fontSize: 11, line: 16)
}

/// The TUI's vector pieces, drawn in one cell. Font glyphs would come from
/// fallback fonts of other widths; these keep the grid and every shape.
public enum CellGlyph: Sendable, Hashable {
    case mark(Mark)
    /// ◎
    case target
    /// ◉
    case logo
    /// ⚑
    case flag
    /// ↵
    case enter
    /// A provider's logo, by its key: it reaches into the cell after it.
    case provider(String)
    /// A braille pattern, its dots as the bits of its code point's last
    /// byte: the TUI's spinner.
    case braille(UInt8)
}

/// One thing a cell scene draws, positioned in points.
public enum CellItem: Sendable {
    /// Text on a line whose top is at `y`; one cell per character, two for
    /// wide ones.
    case text(x: Double, y: Double, String, RGBA, bold: Bool)
    case glyph(x: Double, y: Double, CellGlyph, RGBA)
    case fill(CGRect, RGBA, radius: Double)
    /// A vertical gradient: a bar's lit fill.
    case shaded(CGRect, top: RGBA, middle: RGBA, bottom: RGBA)
    /// A rounded box. `gaps` are x ranges of its top border left open for a
    /// title.
    case box(CGRect, RGBA, radius: Double, gaps: [ClosedRange<Double>])
    /// Vertical stripes `period` apart, half on and half off.
    case stripes(CGRect, RGBA, period: Double)
    case line(from: CGPoint, to: CGPoint, RGBA, width: Double, dash: [Double])
}

/// An age that counts up on its own, as a widget's must between reloads:
/// set as live text over the scene, its right edge at `right`.
public struct LiveAge: Sendable {
    public var right: Double
    public var y: Double
    public var date: Date
    public var color: RGBA
    /// Painted behind it, so it can sit on a box's border.
    public var background: RGBA?
}

/// A drawn grid of styled cells and the TUI's vector pieces.
public struct CellScene: Sendable {
    public var size: CGSize
    public var metrics: CellMetrics
    public var items: [CellItem] = []
    public var live: [LiveAge] = []
    /// Named y positions, such as where a pinned part ends.
    public var marks: [String: Double] = [:]
    /// Named areas, such as a keycap and its label.
    public var regions: [String: CGRect] = [:]

    public init(size: CGSize, metrics: CellMetrics, items: [CellItem] = [], live: [LiveAge] = []) {
        self.size = size
        self.metrics = metrics
        self.items = items
        self.live = live
    }
}

/// Draws any `CellScene`, crisply at any scale.
public struct CellCanvas: View {
    public var scene: CellScene

    public init(scene: CellScene) { self.scene = scene }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, _ in
            let m = scene.metrics
            for item in scene.items {
                switch item {
                case .fill(let r, let c, let radius):
                    ctx.fill(Path(roundedRect: r, cornerRadius: radius, style: .continuous), with: .color(Color(c)))
                case .shaded(let r, let top, let mid, let bottom):
                    ctx.fill(Path(r), with: .linearGradient(
                        Gradient(stops: [.init(color: Color(top), location: 0), .init(color: Color(mid), location: 0.45),
                                         .init(color: Color(bottom), location: 1)]),
                        startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
                case .box(let r, let c, let radius, let gaps):
                    var box = ctx
                    if !gaps.isEmpty {
                        box.clip(to: Self.outside(gaps, of: r), style: FillStyle(eoFill: true))
                    }
                    box.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius, style: .continuous),
                               with: .color(Color(c)), lineWidth: 1)
                case .stripes(let r, let c, let period):
                    var x = r.minX
                    var p = Path()
                    while x < r.maxX {
                        p.addRect(CGRect(x: x, y: r.minY, width: min(period / 2, r.maxX - x), height: r.height))
                        x += period
                    }
                    ctx.fill(p, with: .color(Color(c)))
                case .line(let a, let b, let c, let w, let dash):
                    var p = Path()
                    p.move(to: a)
                    p.addLine(to: b)
                    ctx.stroke(p, with: .color(Color(c)), style: StrokeStyle(lineWidth: w, dash: dash.map { CGFloat($0) }))
                case .text(let x, let y, let s, let c, let bold):
                    Self.drawText(&ctx, s, x: x, y: y, color: c, bold: bold, metrics: m)
                case .glyph(let x, let y, let g, let c):
                    Self.drawGlyph(&ctx, g, x: x, y: y, color: c, metrics: m)
                }
            }
        }
        .frame(width: scene.size.width, height: scene.size.height)
        .overlay(alignment: .topLeading) {
            ForEach(Array(scene.live.enumerated()), id: \.offset) { _, a in
                Text(.currentDate, format: .reference(to: a.date, allowedFields: [.minute, .hour, .day], maxFieldCount: 1))
                    .font(Self.font(scene.metrics, bold: false))
                    .foregroundStyle(Color(a.color))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, a.background == nil ? 0 : scene.metrics.cell)
                    .frame(height: scene.metrics.line)
                    .background(a.background.map { Color($0) } ?? .clear)
                    .frame(width: a.right, alignment: .trailing)
                    .offset(y: a.y)
            }
        }
    }

    /// The scene's whole area less the gaps, for an even-odd clip.
    static func outside(_ gaps: [ClosedRange<Double>], of r: CGRect) -> Path {
        var p = Path(r.insetBy(dx: -2, dy: -2))
        for g in gaps {
            p.addRect(CGRect(x: g.lowerBound, y: r.minY - 2, width: g.upperBound - g.lowerBound, height: 4))
        }
        return p
    }

    static func font(_ m: CellMetrics, bold: Bool) -> Font {
        .system(size: m.fontSize, weight: bold ? .bold : .regular, design: .monospaced)
    }

    /// ASCII in runs, at its own advance; everything else one character at
    /// a time, centered in its cells.
    static func drawText(_ ctx: inout GraphicsContext, _ s: String, x: Double, y: Double, color: RGBA, bold: Bool,
                         metrics m: CellMetrics) {
        let font = font(m, bold: bold)
        // Wide characters come from a fallback font about one em wide; a
        // little larger, they fill their two cells as a terminal's do.
        let wide = Font.system(size: m.fontSize * 1.1, weight: bold ? .bold : .regular, design: .monospaced)
        let mid = y + m.line / 2
        var col = 0
        var run = ""
        var runStart = 0
        func flush() {
            guard !run.isEmpty else { return }
            let t = Text(verbatim: run).font(font).foregroundColor(Color(color))
            ctx.draw(t, at: CGPoint(x: x + Double(runStart) * m.cell, y: mid), anchor: .leading)
            run = ""
        }
        for ch in s {
            let w = CellText.width(ch)
            if ch.isASCII {
                if run.isEmpty { runStart = col }
                run.append(ch)
            } else {
                flush()
                if ch != " " {
                    let t = Text(verbatim: String(ch)).font(w == 2 ? wide : font).foregroundColor(Color(color))
                    ctx.draw(t, at: CGPoint(x: x + (Double(col) + Double(w) / 2) * m.cell, y: mid), anchor: .center)
                }
            }
            col += w
        }
        flush()
    }

    static func drawGlyph(_ ctx: inout GraphicsContext, _ g: CellGlyph, x: Double, y: Double, color c: RGBA,
                          metrics m: CellMetrics) {
        let fs = m.fontSize
        let cx = x + m.cell / 2
        let cy = y + m.line / 2 + 0.03 * fs
        let color = GraphicsContext.Shading.color(Color(c))
        func circle(_ d: Double) -> Path { Path(ellipseIn: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)) }
        switch g {
        case .mark(.up):
            ctx.fill(circle(0.56 * fs), with: color)
        case .mark(.degraded):
            let w = 0.64 * fs, h = 0.56 * fs
            var p = Path()
            p.move(to: CGPoint(x: cx, y: cy - h * 0.58))
            p.addLine(to: CGPoint(x: cx + w / 2, y: cy + h * 0.42))
            p.addLine(to: CGPoint(x: cx - w / 2, y: cy + h * 0.42))
            p.closeSubpath()
            ctx.fill(p, with: color)
        case .mark(.down):
            let r = 0.24 * fs
            var p = Path()
            p.move(to: CGPoint(x: cx - r, y: cy - r))
            p.addLine(to: CGPoint(x: cx + r, y: cy + r))
            p.move(to: CGPoint(x: cx + r, y: cy - r))
            p.addLine(to: CGPoint(x: cx - r, y: cy + r))
            ctx.stroke(p, with: color, style: StrokeStyle(lineWidth: 0.15 * fs, lineCap: .round))
        case .mark(.unknown):
            ctx.stroke(circle(0.5 * fs), with: color, lineWidth: 0.09 * fs)
        case .mark(.offline):
            let d = 0.5 * fs
            ctx.stroke(circle(d), with: color, style: StrokeStyle(lineWidth: 0.09 * fs, dash: [Double.pi * d / 12, Double.pi * d / 12]))
        case .target:
            ctx.stroke(circle(0.6 * fs), with: color, lineWidth: 0.075 * fs)
            ctx.stroke(circle(0.28 * fs), with: color, lineWidth: 0.075 * fs)
        case .logo:
            ctx.stroke(circle(0.6 * fs), with: color, lineWidth: 0.08 * fs)
            ctx.fill(circle(0.32 * fs), with: color)
        case .flag:
            var pole = Path()
            pole.move(to: CGPoint(x: cx - 0.22 * fs, y: cy - 0.34 * fs))
            pole.addLine(to: CGPoint(x: cx - 0.22 * fs, y: cy + 0.36 * fs))
            ctx.stroke(pole, with: color, style: StrokeStyle(lineWidth: 0.08 * fs, lineCap: .round))
            var flag = Path()
            flag.move(to: CGPoint(x: cx - 0.22 * fs, y: cy - 0.34 * fs))
            flag.addLine(to: CGPoint(x: cx + 0.3 * fs, y: cy - 0.18 * fs))
            flag.addLine(to: CGPoint(x: cx - 0.22 * fs, y: cy + 0.02 * fs))
            flag.closeSubpath()
            ctx.fill(flag, with: color)
        case .enter:
            var p = Path()
            p.move(to: CGPoint(x: cx + 0.24 * fs, y: cy - 0.3 * fs))
            p.addLine(to: CGPoint(x: cx + 0.24 * fs, y: cy + 0.08 * fs))
            p.addLine(to: CGPoint(x: cx - 0.26 * fs, y: cy + 0.08 * fs))
            p.move(to: CGPoint(x: cx - 0.1 * fs, y: cy - 0.08 * fs))
            p.addLine(to: CGPoint(x: cx - 0.27 * fs, y: cy + 0.08 * fs))
            p.addLine(to: CGPoint(x: cx - 0.1 * fs, y: cy + 0.24 * fs))
            ctx.stroke(p, with: color, style: StrokeStyle(lineWidth: 0.09 * fs, lineCap: .round, lineJoin: .round))
        case .provider(let key):
            drawLogo(&ctx, key, x: x, y: y, color: c, metrics: m)
        case .braille(let bits):
            // Dots 1–3 and 7 down the left, 4–6 and 8 down the right; three
            // rows sit on the middle when the fourth is empty.
            let places = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
            let d = 0.16 * fs
            let middle = bits & 0xC0 == 0 ? 1.0 : 1.5
            for (bit, (col, row)) in places.enumerated() where bits & (1 << bit) != 0 {
                let px = cx + (Double(col) - 0.5) * 0.3 * fs
                let py = cy + (Double(row) - middle) * 0.24 * fs
                ctx.fill(Path(ellipseIn: CGRect(x: px - d / 2, y: py - d / 2, width: d, height: d)), with: color)
            }
        }
    }
}

/// Display widths on the cell grid: wide East Asian characters take two
/// cells, combining marks none.
public enum CellText {
    public static func width(_ ch: Character) -> Int {
        guard let s = ch.unicodeScalars.first else { return 0 }
        let v = s.value
        if v < 0x1100 { return 1 }
        if s.properties.generalCategory == .nonspacingMark { return 0 }
        switch v {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
             0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }

    public static func width(_ s: String) -> Int { s.reduce(0) { $0 + width($1) } }

    /// At most `n` cells, ending in "…" when cut.
    public static func truncate(_ s: String, _ n: Int) -> String {
        guard width(s) > n else { return s }
        guard n > 0 else { return "" }
        var out = ""
        var w = 0
        for ch in s {
            let cw = width(ch)
            if w + cw > n - 1 { break }
            out.append(ch)
            w += cw
        }
        // "Relay…", never "Relay …".
        while out.last?.isWhitespace == true { out.removeLast() }
        return out + "…"
    }

    /// A route in at most `n` cells, cut as the Native renderer cuts it so
    /// both ends stay readable: a part that fits an equal share keeps its
    /// width, and longer ones split the rest.
    public static func route(_ parts: [String], _ n: Int) -> String {
        let arrow = " → "
        let whole = parts.joined(separator: arrow)
        var room = n - width(arrow) * (parts.count - 1)
        guard width(whole) > n, parts.count > 1, room >= 3 * parts.count else { return truncate(whole, n) }
        var out = parts
        var left = parts.count
        for i in parts.indices.sorted(by: { width(parts[$0]) < width(parts[$1]) }) {
            out[i] = truncate(parts[i], room / left)
            room -= width(out[i])
            left -= 1
        }
        return out.joined(separator: arrow)
    }

    /// Cut or padded with spaces to exactly `n` cells.
    public static func pad(_ s: String, _ n: Int) -> String {
        let t = truncate(s, n)
        return t + String(repeating: " ", count: max(0, n - width(t)))
    }

    public static func padLeft(_ s: String, _ n: Int) -> String {
        String(repeating: " ", count: max(0, n - width(s))) + s
    }
}
