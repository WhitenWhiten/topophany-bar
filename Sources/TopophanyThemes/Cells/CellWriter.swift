import Foundation
import TopophanySections

/// The cells renderer's palette: the TUI's slots, from a theme's tokens.
struct CellsPalette {
    var ink, inkHigh, selection, key, line, track: RGBA
    var text, muted, faint, glow, accent, accent2, kind: RGBA
    var up, warn, down, unknown: RGBA

    init(_ theme: Theme) {
        let fallback = ThemeStore.terminal
        func c(_ slot: String) -> RGBA { theme.color(slot) ?? fallback.color(slot) ?? RGBA(1, 0, 1) }
        ink = c("ink")
        inkHigh = c("inkHigh")
        selection = c("selection")
        key = c("key")
        line = c("line")
        track = c("track")
        text = c("text")
        muted = c("muted")
        faint = c("faint")
        glow = theme.color("glow") ?? RGBA(1, 1, 1)
        accent = c("accent")
        accent2 = c("accent2")
        kind = c("kind")
        up = c("up")
        warn = c("warning")
        down = c("down")
        unknown = c("unknown")
    }

    func tone(_ m: Mark) -> RGBA {
        switch m {
        case .up: up
        case .degraded: warn
        case .down: down
        case .unknown, .offline: unknown
        }
    }

    /// The TUI's loadColor: accent until a reading nears its limit, warning
    /// past it.
    func load(_ v: Double, limit: Double?) -> RGBA {
        var l = limit ?? 100
        if !(l > 0) || l > 100 { l = 100 }
        if v > l { return warn }
        let t = min(1, max(0, (v / l - 0.55) / 0.45))
        return accent.mix(warn, t * t)
    }

    /// A pill's background: the status color at 18% over ink.
    func pillBackground(_ m: Mark) -> RGBA {
        m == .unknown || m == .offline ? key : ink.mix(tone(m), 0.18)
    }
}

/// A piece of a line, in cells.
enum Seg {
    case text(String, RGBA, bold: Bool = false)
    case glyph(CellGlyph, RGBA)
    /// A meter: the reading against its limit; `nil` when unknown.
    case bar(cells: Int, percent: Double?, limit: Double?, color: RGBA, withheld: Bool)
    /// The TUI's sparks: one block per reading.
    case sparks([Double], top: Double, RGBA)
    case pill(String, fg: RGBA, bg: RGBA)
    case key(String)
    /// ━ in runs of color.
    case rule([(Int, RGBA)])
    /// ╌
    case dashes(Int, RGBA)

    var width: Int {
        switch self {
        case .text(let s, _, _), .pill(let s, _, _), .key(let s): CellText.width(s)
        case .glyph: 1
        case .bar(let n, _, _, _, _): n
        case .sparks(let v, _, _): v.count
        case .rule(let parts): parts.reduce(0) { $0 + $1.0 }
        case .dashes(let n, _): n
        }
    }

    static func t(_ s: String, _ c: RGBA, bold: Bool = false) -> Seg { .text(s, c, bold: bold) }
    static func mark(_ m: Mark, _ p: CellsPalette) -> Seg { .glyph(.mark(m), p.tone(m)) }
}

/// Lays lines and boxes onto a cell scene, top to bottom.
struct CellWriter {
    struct Frame {
        /// Where text starts and how many columns it has.
        var x: Double
        var columns: Int
    }

    struct BoxStyle {
        /// Gap above a box.
        var margin: Double
        /// From the box's border to its first line, and after its last.
        var padTop: Double
        var padBottom: Double
        /// How far the title line sits above the padding box.
        var titleRise: Double
        var radius: Double

        static let panel = BoxStyle(margin: 15, padTop: 9, padBottom: 5, titleRise: 10, radius: 6)
        static let widget = BoxStyle(margin: 12, padTop: 7, padBottom: 4, titleRise: 9, radius: 6)
    }

    var metrics: CellMetrics
    var palette: CellsPalette
    var width: Double
    var y: Double = 0
    var items: [CellItem] = []
    var frame: Frame
    /// Monochrome (another app in front): boxes become plain headings.
    var plain = false

    var cell: Double { metrics.cell }
    var lineHeight: Double { metrics.line }

    init(metrics: CellMetrics, palette: CellsPalette, width: Double, frame: Frame) {
        self.metrics = metrics
        self.palette = palette
        self.width = width
        self.frame = frame
    }

    // MARK: lines

    /// One line: `left` from the start, `right` against the end.
    mutating func line(_ left: [Seg], _ right: [Seg] = [], in f: Frame? = nil) {
        let f = f ?? frame
        draw(left, x: f.x, y: y)
        let rw = right.reduce(0) { $0 + $1.width }
        if rw > 0 { draw(right, x: f.x + Double(f.columns - rw) * cell, y: y) }
        y += lineHeight
    }

    mutating func blank(_ h: Double? = nil) { y += h ?? lineHeight }

    mutating func draw(_ segs: [Seg], x: Double, y: Double) {
        var col = 0.0
        for s in segs {
            draw(s, x: x + col * cell, y: y)
            col += Double(s.width)
        }
    }

    mutating func draw(_ s: Seg, x: Double, y: Double) {
        let p = palette
        let w = Double(s.width) * cell
        switch s {
        case .text(let str, let c, let bold):
            items.append(.text(x: x, y: y, str, c, bold: bold))
        case .glyph(let g, let c):
            items.append(.glyph(x: x, y: y, g, c))
        case .bar(_, let percent, let limit, let c, let withheld):
            let h = 10 * metrics.fontSize / 12
            let r = CGRect(x: x, y: y + lineHeight / 2 - h / 2 + 0.5, width: w, height: h)
            if withheld || percent == nil {
                items.append(.stripes(r, p.track, period: cell))
            } else if let v = percent {
                items.append(.fill(r, p.track, radius: 0))
                let fill = CGRect(x: r.minX, y: r.minY, width: r.width * min(100, max(0, v)) / 100, height: r.height)
                items.append(.shaded(fill, top: c.mix(RGBA(1, 1, 1), 0.26), middle: c, bottom: c.mix(RGBA(0, 0, 0), 0.18)))
                if let l = limit, l < 100 {
                    let lx = r.minX + r.width * l / 100
                    items.append(.fill(CGRect(x: lx, y: r.minY - 3, width: 1, height: r.height + 6), p.warn.opacity(0.65), radius: 0))
                }
            }
        case .sparks(let values, let top, let c):
            let full = metrics.fontSize * 1.18
            let bottom = y + lineHeight / 2 + full / 2
            for (i, v) in values.enumerated() {
                let k = max(1, min(8, Int((v / max(top, 1e-9) * 7).rounded()) + 1))
                let h = full * Double(k) / 8
                items.append(.fill(CGRect(x: x + Double(i) * cell, y: bottom - h, width: cell + 0.05, height: h), c, radius: 0))
            }
        case .pill(let str, let fg, let bg):
            items.append(.fill(CGRect(x: x, y: y, width: w, height: lineHeight), bg, radius: 0))
            items.append(.text(x: x, y: y, str, fg, bold: true))
        case .key(let str):
            items.append(.fill(CGRect(x: x, y: y - 1, width: w, height: lineHeight + 2), p.key, radius: 3))
            items.append(.text(x: x, y: y, str, p.accent, bold: true))
        case .rule(let parts):
            var cx = x
            for (n, c) in parts where n > 0 {
                let len = Double(n) * cell
                items.append(.fill(CGRect(x: cx, y: y + lineHeight / 2 - 1.1, width: len, height: 2.2), c, radius: 0))
                cx += len
            }
        case .dashes(let n, let c):
            items.append(.line(from: CGPoint(x: x + cell * 0.1, y: y + lineHeight / 2), to: CGPoint(x: x + Double(n) * cell, y: y + lineHeight / 2),
                               c, width: 1, dash: [cell * 0.4, cell * 0.1]))
        }
    }

    // MARK: boxes

    /// A rounded box with its title set in the top border, and metadata
    /// right-aligned in the border too. `x0`…`x1` is its outer edge.
    mutating func box(_ title: [Seg], _ right: [Seg] = [], x0: Double, x1: Double, style: BoxStyle,
                      tint: RGBA? = nil, body: (inout CellWriter) -> Void) {
        let p = palette
        if plain {
            // Monochrome: a plain heading, no border.
            y += style.margin * 0.4
            let f = Frame(x: x0 + 1, columns: Int(((x1 - x0) / cell).rounded(.down)) - 1)
            line(title, right, in: f)
            let saved = frame
            frame = Frame(x: x0 + 1, columns: f.columns)
            body(&self)
            frame = saved
            y += style.padBottom
            return
        }
        let start = items.count
        let top = y + style.margin
        let titleY = top + 1 - style.titleRise
        let titleX = x0 + cell - 2
        let rightEnd = x1 - cell + 2
        let saved = frame
        frame = Frame(x: x0 + cell, columns: Int(((x1 - x0 - 2 * cell) / cell).rounded()))
        y = top + 1 + style.padTop
        body(&self)
        let bottom = y + style.padBottom + 1
        frame = saved
        var titleItems = CellWriter(metrics: metrics, palette: p, width: width, frame: frame)
        let tw = Double(title.reduce(0) { $0 + $1.width }) * cell
        titleItems.draw(title, x: titleX, y: titleY)
        var gaps = [titleX...(titleX + tw)]
        let rw = Double(right.reduce(0) { $0 + $1.width }) * cell
        if rw > 0 {
            titleItems.draw(right, x: rightEnd - rw, y: titleY)
            gaps.append((rightEnd - rw)...rightEnd)
        }
        let rect = CGRect(x: x0, y: top, width: x1 - x0, height: bottom - top)
        items.insert(.box(rect, tint ?? p.line, radius: style.radius, gaps: gaps), at: start)
        items += titleItems.items
        y = bottom
    }

    /// The focused row's background and accent bar, from border to border.
    mutating func focus(x0: Double, x1: Double, top: Double, height: Double) {
        items.append(.fill(CGRect(x: x0 + 1, y: top, width: x1 - x0 - 2, height: height), palette.selection, radius: 0))
        items.append(.fill(CGRect(x: x0 + 1, y: top, width: 2, height: height), palette.accent, radius: 0))
    }

    /// The TUI's bigText: a 3×5 pixel font, each pixel row a shade of the
    /// color, lit from above.
    mutating func bigDigits(_ s: String, color: RGBA, x: Double, y: Double, height: Double) {
        let p = palette
        let shade = [color.mix(p.glow, 0.4), color.mix(p.glow, 0.18), color, color.mix(p.ink, 0.14), color.mix(p.ink, 0.28)]
        let ph = height / 6
        for (k, ch) in s.enumerated() {
            guard let rows = Self.font[ch] else { continue }
            for (ry, row) in rows.enumerated() {
                for (rx, px) in row.enumerated() where px == "#" {
                    let r = CGRect(x: x + Double(rx + 4 * k) * cell, y: y + Double(ry) * ph, width: cell + 0.35, height: ph + 0.35)
                    items.append(.fill(r, shade[ry], radius: 0))
                }
            }
        }
    }

    static func bigWidth(_ s: String) -> Int { max(0, 4 * s.count - 1) }

    static let font: [Character: [String]] = [
        "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", ".##", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
        "-": ["...", "...", "###", "...", "..."],
    ]
}
