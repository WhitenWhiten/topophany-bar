import Foundation
import TopophanySections

/// The cells renderer's palette: the TUI's slots, from a theme's tokens.
struct CellsPalette {
    var ink, inkHigh, selection, key, line, track: RGBA
    var text, muted, faint, glow, accent, accent2, kind: RGBA
    var up, warn, down, unknown: RGBA
    /// A texture's ink.
    var grain: RGBA
    var box: CellBoxStyle
    var meter: CellMeterStyle
    var texture: Texture

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
        grain = theme.color("grain") ?? RGBA(0, 0, 0, 0)
        box = CellBoxStyle(rawValue: theme.style("box")) ?? .rounded
        meter = CellMeterStyle(rawValue: theme.style("meter")) ?? .blocks
        texture = Texture(theme.style("texture"))
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
    /// A provider's logo by its key, and the space after it it reaches into.
    case logo(String, RGBA)
    /// A meter: the reading against its limit; `nil` when unknown.
    case bar(cells: Int, percent: Double?, limit: Double?, color: RGBA, withheld: Bool)
    /// The TUI's sparks: one block per reading.
    case sparks([Double], top: Double, RGBA)
    /// A check's recent samples in `cells` cells, newest at the right, on
    /// the track; withheld, the track striped; none held, nothing.
    case samples(ServiceCardModel.History, cells: Int)
    case pill(String, fg: RGBA, bg: RGBA)
    case key(String)
    /// ━ in runs of color.
    case rule([(Int, RGBA)])
    /// ╌
    case dashes(Int, RGBA)
    /// A day ribbon: one color per cell, gaps at `midnights` (fractions of
    /// its width) and a tick at its middle.
    case ribbon([RGBA], midnights: [Double], now: RGBA)

    var width: Int {
        switch self {
        case .text(let s, _, _), .pill(let s, _, _), .key(let s): CellText.width(s)
        case .glyph: 1
        case .logo: 2
        case .bar(let n, _, _, _, _): n
        case .sparks(let v, _, _): v.count
        case .samples(_, let n): n
        case .rule(let parts): parts.reduce(0) { $0 + $1.0 }
        case .dashes(let n, _): n
        case .ribbon(let cells, _, _): cells.count
        }
    }

    static func t(_ s: String, _ c: RGBA, bold: Bool = false) -> Seg { .text(s, c, bold: bold) }
    static func mark(_ m: Mark, _ p: CellsPalette) -> Seg { .glyph(.mark(m), p.tone(m)) }

    /// A provider's logo where the app has one, as the TUI leads a name with
    /// it; its node's kind's glyph for a provider the app doesn't know;
    /// nothing where it names none.
    static func logo(_ provider: String, kind: String = "", _ p: CellsPalette) -> [Seg] {
        guard let key = ProviderLogo.key(provider: provider, kind: kind) else { return [] }
        return [.logo(key, p.logo(Provider.known(provider)))]
    }
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
    var live: [LiveAge] = []
    /// Where the keyboard's focus is drawn.
    var focused: CGRect?
    var frame: Frame
    /// Monochrome (another app in front): boxes become plain headings.
    var plain = false
    /// Where the last box's right-hand title was drawn, if it had one.
    var titleRight: CGRect?

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
        case .logo(let key, let c):
            items.append(.glyph(x: x, y: y, .provider(key), c))
        case .bar(_, let percent, let limit, let c, let withheld):
            let h = 10 * metrics.fontSize / 12
            let r = CGRect(x: x, y: y + lineHeight / 2 - h / 2 + 0.5, width: w, height: h)
            if withheld || percent == nil {
                items.append(.stripes(r, p.track, period: cell))
            } else if let v = percent {
                meter(r, cells: Int((w / cell).rounded()), fraction: min(100, max(0, v)) / 100, color: c)
                if let l = limit, l < 100 {
                    let lx = r.minX + r.width * l / 100
                    items.append(.fill(CGRect(x: lx, y: r.minY - 3, width: 1, height: r.height + 6), p.warn.opacity(0.65), radius: 0))
                }
            }
        case .sparks(let values, let top, let c):
            let full = metrics.fontSize * 1.18
            let bottom = y + lineHeight / 2 + full / 2
            let d = 0.16 * metrics.fontSize
            for (i, v) in values.enumerated() {
                let share = v / max(top, 1e-9)
                switch p.meter {
                case .blocks:
                    let h = full * Double(max(1, min(8, Int((share * 7).rounded()) + 1))) / 8
                    items.append(.fill(CGRect(x: x + Double(i) * cell, y: bottom - h, width: cell + 0.05, height: h), c, radius: 0))
                case .shade:
                    // A hairline a reading, as a pen on a drum draws it.
                    let h = max(1, full * min(1, share))
                    items.append(.fill(CGRect(x: x + (Double(i) + 0.5) * cell - 0.5, y: bottom - h, width: 1, height: h), c, radius: 0))
                case .braille:
                    let k = max(1, min(4, Int((share * 4).rounded())))
                    let pitch = (full - d) / 3
                    let h = d + Double(k - 1) * pitch
                    items.append(.dots(CGRect(x: x + (Double(i) + 0.5) * cell - d / 2, y: bottom - h, width: d, height: h), c,
                                       diameter: d, columns: 1, rows: k))
                }
            }
        case .samples(let history, let n):
            drawSamples(history, cells: n, x: x, y: y)
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
        case .ribbon(let cells, let midnights, let now):
            let h = 6 * metrics.fontSize / 12
            let top = y + lineHeight / 2 - h / 2
            for (i, c) in cells.enumerated() {
                items.append(.fill(CGRect(x: x + Double(i) * cell, y: top, width: cell + 0.05, height: h), c, radius: 0))
            }
            for m in midnights {
                items.append(.fill(CGRect(x: x + w * m - 0.5, y: top, width: 1, height: h), p.ink, radius: 0))
            }
            items.append(.fill(CGRect(x: x + w / 2 - 1, y: top - 4, width: 2, height: h + 8), now, radius: 0))
        }
    }

    /// Recent samples as the TUI draws them on a card: a passing one as
    /// tall as it took against the slowest shown, in the palette's meter and
    /// never a full cell, so rows stay apart; a failure its mark (✖ failed,
    /// ▲ against policy, ○ otherwise), and `·` where none was taken.
    mutating func drawSamples(_ history: ServiceCardModel.History, cells n: Int, x: Double, y: Double) {
        let p = palette
        let full = metrics.fontSize * 1.18
        let band = CGRect(x: x, y: y + lineHeight / 2 - full / 2, width: Double(n) * cell, height: full)
        let samples: [ServiceCardModel.Sample]
        switch history {
        case .samples(let s): samples = s
        case .none: return
        case .withheld:
            items.append(.stripes(band.insetBy(dx: 0, dy: full * 0.18), p.track, period: cell))
            return
        }
        let shown = Array(samples.suffix(n))
        let first = n - shown.count
        let top = max(1, shown.compactMap { if case .ok(let v) = $0 { v } else { nil } }.max() ?? 1)
        let ok = p.accent.mix(p.muted, 0.28)
        let d = 0.16 * metrics.fontSize
        switch p.meter {
        case .blocks: items.append(.fill(band, p.track, radius: 0))
        case .shade: items.append(.fill(CGRect(x: band.minX, y: band.maxY - 1, width: band.width, height: 1), p.faint.opacity(0.6), radius: 0))
        case .braille: break
        }
        // Dusk draws a dot matrix in its meters' own grid: two columns of
        // four dots a cell, unlit as the track, so a cell no sample lights
        // reads as empty rather than as a dot of its own.
        let mh = 10 * metrics.fontSize / 12
        let mr = CGRect(x: x, y: y + lineHeight / 2 - mh / 2 + 0.5, width: Double(n) * cell, height: mh)
        let px = (mr.width - d) / Double(max(1, 2 * n - 1)), py = (mh - d) / 3
        func matrix(_ i: Int, cells: Int = 1, lit k: Int = 0) {
            let left = mr.minX + Double(2 * i) * px, wide = d + Double(2 * cells - 1) * px
            items.append(.dots(CGRect(x: left, y: mr.minY, width: wide, height: mh), p.line, diameter: d, columns: 2 * cells, rows: 4))
            if k > 0 {
                let h = d + Double(k - 1) * py
                items.append(.dots(CGRect(x: left, y: mr.maxY - h, width: wide, height: h), p.accent, diameter: d, columns: 2 * cells, rows: k))
            }
        }
        if p.meter == .braille, first > 0 {
            matrix(0, cells: first)
        }
        for (i, s) in shown.enumerated() {
            let cx = x + Double(first + i) * cell
            switch s {
            case .ok(let v):
                let share = min(1, v / top)
                switch p.meter {
                case .blocks:
                    let h = full * Double(max(1, min(7, Int((share * 6).rounded()) + 1))) / 8
                    items.append(.fill(CGRect(x: cx, y: band.maxY - h, width: cell + 0.05, height: h), ok, radius: 0))
                case .shade:
                    let h = max(1, full * 7 / 8 * share)
                    items.append(.fill(CGRect(x: cx + cell / 2 - 0.5, y: band.maxY - h, width: 1, height: h), ok, radius: 0))
                case .braille:
                    matrix(first + i, lit: max(1, min(4, Int((share * 4).rounded()))))
                }
            case .none:
                if p.meter == .braille {
                    matrix(first + i)
                } else {
                    items.append(.text(x: cx, y: y, "·", p.faint, bold: false))
                }
            case .fail:
                items.append(.glyph(x: cx, y: y, .mark(.down), p.down))
            case .policy:
                items.append(.glyph(x: cx, y: y, .mark(.degraded), p.warn))
            case .error, .unknown:
                items.append(.glyph(x: cx, y: y, .mark(.unknown), p.unknown))
            }
        }
    }

    /// A reading in `cells` cells from `r`'s left, in the palette's meter.
    mutating func meter(_ r: CGRect, cells n: Int, fraction f: Double, color c: RGBA) {
        let p = palette
        switch p.meter {
        case .blocks:
            // Each cell a block, a hairline from the next; the reading fills
            // whole cells and a share of the last.
            let lit = f * Double(n)
            for i in 0..<n {
                let b = CGRect(x: r.minX + Double(i) * cell + 0.5, y: r.minY, width: cell - 1, height: r.height)
                items.append(.fill(b, p.track, radius: 0))
                let share = min(1, max(0, lit - Double(i)))
                if share > 0 { items.append(.fill(CGRect(x: b.minX, y: b.minY, width: b.width * share, height: b.height), c, radius: 0)) }
            }
        case .shade:
            // A dotted track, the reading a halftone over it with a rule
            // beneath.
            items.append(.dots(r.insetBy(dx: 0.5, dy: r.height * 0.32), p.faint.opacity(0.7), diameter: 1, columns: 2 * n, rows: 2))
            let fill = CGRect(x: r.minX, y: r.minY, width: r.width * f, height: r.height)
            items.append(.fill(fill, p.ink, radius: 0))
            items.append(.hatch(fill, c, period: 2.2))
            items.append(.fill(CGRect(x: fill.minX, y: fill.maxY - 1, width: fill.width, height: 1), c, radius: 0))
        case .braille:
            // Two columns of four dots a cell, as braille's ⣿.
            let d = 0.16 * metrics.fontSize
            let columns = 2 * n
            let pitch = (r.width - d) / Double(columns - 1)
            items.append(.dots(r, p.line, diameter: d, columns: columns, rows: 4))
            let k = Int((f * Double(columns)).rounded())
            if k > 0 {
                items.append(.dots(CGRect(x: r.minX, y: r.minY, width: d + Double(k - 1) * pitch, height: r.height), c,
                                   diameter: d, columns: k, rows: 4))
            }
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
            titleRight = nil
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
        titleRight = nil
        var gaps = [titleX...(titleX + tw)]
        let rw = Double(right.reduce(0) { $0 + $1.width }) * cell
        if rw > 0 {
            titleRight = CGRect(x: rightEnd - rw, y: titleY, width: rw, height: lineHeight)
            titleItems.draw(right, x: rightEnd - rw, y: titleY)
            gaps.append((rightEnd - rw)...rightEnd)
        }
        let rect = CGRect(x: x0, y: top, width: x1 - x0, height: bottom - top)
        items.insert(.box(rect, tint ?? p.line, radius: style.radius, gaps: gaps, style: p.box), at: start)
        items += titleItems.items
        y = bottom
    }

    /// The focused row's background and accent bar, from border to border.
    mutating func focus(x0: Double, x1: Double, top: Double, height: Double) {
        focused = CGRect(x: x0, y: top, width: x1 - x0, height: height)
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
