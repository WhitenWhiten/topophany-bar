import SwiftUI
import TopophanySections

/// The cards renderer's colors for one appearance. Native leaves every
/// slot to the system; a theme of this renderer may fill any of them.
struct CardsPalette {
    var isDark: Bool
    var l1: Color
    var l2: Color
    var l3: Color
    var sep: Color
    var card: Color
    var cardEdge: Color
    var fill: Color
    var fill2: Color
    var panel: Color
    var up: Color
    var warn: Color
    var down: Color
    var unknown: Color
    var accent: Color
    var accent2: Color
    var on = Color.white

    static func resolve(_ ctx: RenderContext) -> CardsPalette {
        let dark = ctx.effectiveScheme == .dark
        let hc = ctx.increaseContrast
        func token(_ slot: String) -> Color? { ctx.theme.color(slot).map(Color.init) }
        var p = dark
            ? CardsPalette(isDark: true,
                           l1: Color(white: 1, opacity: 0.92),
                           l2: Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: hc ? 0.8 : 0.62),
                           l3: Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: hc ? 0.62 : 0.36),
                           sep: Color(white: 1, opacity: hc ? 0.22 : 0.08),
                           card: Color(white: 1, opacity: 0.068), cardEdge: Color(white: 1, opacity: hc ? 0.3 : 0.05),
                           fill: Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.36),
                           fill2: Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.2),
                           panel: Color(.sRGB, red: 32 / 255, green: 32 / 255, blue: 38 / 255, opacity: 0.55),
                           up: .green, warn: .orange, down: .red, unknown: .gray, accent: .accentColor, accent2: .cyan)
            : CardsPalette(isDark: false,
                           l1: Color(white: 0, opacity: 0.86),
                           l2: Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: hc ? 0.85 : 0.68),
                           l3: Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: hc ? 0.66 : 0.4),
                           sep: Color(white: 0, opacity: hc ? 0.2 : 0.07),
                           card: Color(white: 1, opacity: 0.64), cardEdge: Color(white: 0, opacity: hc ? 0.25 : 0.035),
                           fill: Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.2),
                           fill2: Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.1),
                           panel: Color(.sRGB, red: 250 / 255, green: 250 / 255, blue: 253 / 255, opacity: 0.6),
                           up: .green, warn: .orange, down: .red, unknown: .gray, accent: .accentColor, accent2: .cyan)
        if ctx.reduceTransparency {
            p.panel = dark ? Color(.sRGB, red: 0.13, green: 0.13, blue: 0.15) : Color(.sRGB, red: 0.96, green: 0.96, blue: 0.97)
            p.card = dark ? Color(white: 1, opacity: 0.09) : Color(white: 1, opacity: 1)
        }
        if let c = token("accent") { p.accent = c }
        if let c = token("accent2") { p.accent2 = c }
        if let c = token("card") { p.card = c }
        if let c = token("cardEdge") { p.cardEdge = c }
        if let c = token("fill") { p.fill = c }
        if let c = token("fill2") { p.fill2 = c }
        if let c = token("panelMaterial"), !ctx.reduceTransparency { p.panel = c }
        if let c = token("up") { p.up = c }
        if let c = token("warning") { p.warn = c }
        if let c = token("down") { p.down = c }
        if let c = token("unknown") { p.unknown = c }
        return p
    }

    func color(_ m: Mark) -> Color {
        switch m {
        case .up: up
        case .degraded: warn
        case .down: down
        case .unknown, .offline: unknown
        }
    }

    /// A pill's or chip's background: the status color at 15%, or a fill.
    func tint(_ m: Mark, _ amount: Double = 0.15) -> Color {
        switch m {
        case .up, .degraded, .down: color(m).opacity(amount)
        case .unknown, .offline: fill2
        }
    }
}

/// The text sizes of the cards renderer, scaled by the Text size setting.
struct CardsType {
    var scale: Double

    func font(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight)
    }

    func mono(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight).monospacedDigit()
    }
}

/// A status mark as the cards renderer draws it: shape first, then color.
/// ● up · ▲ degraded · ✖ down (a disc with a cross) · ○ unknown · ◌ offline
struct CardMark: View {
    var mark: Mark
    var size: Double
    var color: Color
    var on: Color = .white

    var body: some View {
        Canvas { ctx, s in
            let k = s.width / 14
            ctx.scaleBy(x: k, y: k)
            switch mark {
            case .up:
                ctx.fill(Path(ellipseIn: CGRect(x: 1.8, y: 1.8, width: 10.4, height: 10.4)), with: .color(color))
            case .degraded:
                var t = Path()
                t.move(to: CGPoint(x: 6.1, y: 1.9))
                t.addQuadCurve(to: CGPoint(x: 7.9, y: 1.9), control: CGPoint(x: 7, y: 0.4))
                t.addLine(to: CGPoint(x: 12.9, y: 11))
                t.addQuadCurve(to: CGPoint(x: 12, y: 12.5), control: CGPoint(x: 13.6, y: 12.5))
                t.addLine(to: CGPoint(x: 2, y: 12.5))
                t.addQuadCurve(to: CGPoint(x: 1.1, y: 11), control: CGPoint(x: 0.4, y: 12.5))
                t.closeSubpath()
                ctx.fill(t, with: .color(color))
                var bar = Path()
                bar.move(to: CGPoint(x: 7, y: 5.2))
                bar.addLine(to: CGPoint(x: 7, y: 8.2))
                ctx.stroke(bar, with: .color(on), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: 6.25, y: 9.45, width: 1.5, height: 1.5)), with: .color(on))
            case .down:
                ctx.fill(Path(ellipseIn: CGRect(x: 1, y: 1, width: 12, height: 12)), with: .color(color))
                var x = Path()
                x.move(to: CGPoint(x: 4.9, y: 4.9))
                x.addLine(to: CGPoint(x: 9.1, y: 9.1))
                x.move(to: CGPoint(x: 9.1, y: 4.9))
                x.addLine(to: CGPoint(x: 4.9, y: 9.1))
                ctx.stroke(x, with: .color(on), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            case .unknown:
                ctx.stroke(Path(ellipseIn: CGRect(x: 2.2, y: 2.2, width: 9.6, height: 9.6)), with: .color(color), lineWidth: 1.6)
            case .offline:
                ctx.stroke(Path(ellipseIn: CGRect(x: 2, y: 2, width: 10, height: 10)), with: .color(color),
                           style: StrokeStyle(lineWidth: 1.5, dash: [2.2, 1.9]))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The Status card's symbol: a matte tile in the verdict's color, and its
/// glyph.
struct HeroSymbol: View {
    var status: StatusSection
    var size: Double
    var palette: CardsPalette

    enum Glyph { case check, bang, cross, dots, noSignal, clock }

    var glyph: Glyph {
        switch status.kind {
        case .verdict(.clear): .check
        case .verdict(.degraded): .bang
        case .verdict(.incidents), .verdict(.down): .cross
        case .verdict: .dots
        case .blind(.starting): .clock
        case .blind: .noSignal
        }
    }

    /// The status color, a shade deeper so the white glyph holds; gray for
    /// unknown and offline.
    var fill: Color {
        switch status.mark {
        case .up, .degraded, .down: palette.color(status.mark).mix(with: .black, by: 0.1)
        case .unknown: Color(rgb: 0x8A8A91)
        case .offline: Color(rgb: 0x6A6A71)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 12 / 44, style: .continuous)
        shape
            .fill(fill)
            .overlay(shape.strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
            .overlay { glyphView }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(palette.isDark ? 0.3 : 0.14), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }

    var glyphView: some View {
        Canvas { ctx, s in
            let k = s.width / 47
            ctx.scaleBy(x: k, y: k)
            let white = GraphicsContext.Shading.color(.white)
            func stroke(_ p: Path, _ w: Double) {
                ctx.stroke(p, with: white, style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
            var p = Path()
            switch glyph {
            case .check:
                p.move(to: CGPoint(x: 14.5, y: 23.5))
                p.addLine(to: CGPoint(x: 20.5, y: 29.5))
                p.addLine(to: CGPoint(x: 32.5, y: 16.5))
                stroke(p, 3.6)
            case .bang:
                p.move(to: CGPoint(x: 23.5, y: 13.5))
                p.addLine(to: CGPoint(x: 23.5, y: 24.5))
                stroke(p, 3.8)
                ctx.fill(Path(ellipseIn: CGRect(x: 21.2, y: 29.3, width: 4.6, height: 4.6)), with: white)
            case .cross:
                p.move(to: CGPoint(x: 16.5, y: 16.5))
                p.addLine(to: CGPoint(x: 30.5, y: 30.5))
                p.move(to: CGPoint(x: 30.5, y: 16.5))
                p.addLine(to: CGPoint(x: 16.5, y: 30.5))
                stroke(p, 3.6)
            case .dots:
                for x in [15.5, 23.5, 31.5] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.4, y: 21.1, width: 4.8, height: 4.8)), with: white)
                }
            case .noSignal:
                for (r, y) in [(15.0, 19.4), (9.6, 23.6), (4.4, 27.6)] {
                    var a = Path()
                    a.addArc(center: CGPoint(x: 23.5, y: y + r * 0.72), radius: r,
                             startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
                    stroke(a, 2.6)
                }
                p.move(to: CGPoint(x: 14, y: 13))
                p.addLine(to: CGPoint(x: 33.6, y: 33))
                stroke(p, 2.8)
            case .clock:
                stroke(Path(ellipseIn: CGRect(x: 13.5, y: 13.5, width: 20, height: 20)), 2.6)
                p.move(to: CGPoint(x: 23.5, y: 17.5))
                p.addLine(to: CGPoint(x: 23.5, y: 23.5))
                p.addLine(to: CGPoint(x: 27.5, y: 26))
                stroke(p, 2.6)
            }
        }
    }
}

/// Diagonal hatching: what is unknown, never left out and never zero.
struct Hatch: View {
    var color: Color
    var line = 2.0
    var gap = 2.0

    var body: some View {
        Canvas { ctx, s in
            let step = line + gap
            var p = Path()
            var x = -s.height
            while x < s.width + s.height {
                p.move(to: CGPoint(x: x, y: s.height))
                p.addLine(to: CGPoint(x: x + s.height, y: 0))
                x += step * 1.4142
            }
            ctx.stroke(p, with: .color(color), lineWidth: line)
        }
    }
}

/// Every configured check by health: up, warn, down and unknown, in that
/// order. One tick per check while each can be told apart, an unknown
/// check a hollow tick; past that, runs of color with the unknown hatched.
struct StackBar: View {
    var counts: (up: Int, warning: Int, down: Int, unknown: Int)
    var palette: CardsPalette
    var height = 6.0
    /// The height it takes: ticks are taller than the runs they replace.
    nonisolated static let tickHeight = 9.0

    /// A tick's width and the gap after it, or nil when ticks would be too
    /// thin to count.
    static func ticks(_ n: Int, width: Double) -> (tick: Double, gap: Double)? {
        guard n > 0 else { return nil }
        for gap in [1.5, 1.0] {
            let tick = (width - gap * Double(n - 1)) / Double(n)
            if tick >= (gap > 1 ? 2.2 : 1.6) { return (tick, gap) }
        }
        return nil
    }

    var total: Int { counts.up + counts.warning + counts.down + counts.unknown }

    var body: some View {
        GeometryReader { g in
            if let t = Self.ticks(total, width: g.size.width) {
                tickView(t)
            } else {
                runs.frame(height: height).frame(maxHeight: .infinity)
            }
        }
        .frame(height: Self.tickHeight)
    }

    func tickView(_ t: (tick: Double, gap: Double)) -> some View {
        let p = palette
        let c = counts
        return Canvas { ctx, s in
            var x = 0.0
            func draw(_ n: Int, _ body: (CGRect) -> Void) {
                for _ in 0..<n {
                    body(CGRect(x: x, y: 0, width: t.tick, height: s.height))
                    x += t.tick + t.gap
                }
            }
            let r = min(1, t.tick / 3)
            // Up is quieter than trouble, so what needs a look stands out.
            draw(c.up) { ctx.fill(Path(roundedRect: $0, cornerRadius: r), with: .color(p.up.opacity(0.78))) }
            draw(c.warning) { ctx.fill(Path(roundedRect: $0, cornerRadius: r), with: .color(p.warn)) }
            draw(c.down) { ctx.fill(Path(roundedRect: $0, cornerRadius: r), with: .color(p.down)) }
            draw(c.unknown) {
                ctx.fill(Path(roundedRect: $0, cornerRadius: r), with: .color(p.unknown.opacity(0.14)))
                ctx.stroke(Path(roundedRect: $0.insetBy(dx: 0.5, dy: 0.5), cornerRadius: max(0, r - 0.5)),
                           with: .color(p.unknown), lineWidth: 1)
            }
        }
    }

    var runs: some View {
        GeometryReader { g in
            let parts: [(Int, Color?, Bool)] = [(counts.up, palette.up, false), (counts.warning, palette.warn, false),
                                                (counts.down, palette.down, false), (counts.unknown, nil, true)]
            let shown = parts.filter { $0.0 > 0 }
            let total = Double(shown.reduce(0) { $0 + $1.0 })
            let gaps = Double(max(0, shown.count - 1)) * 2
            let minW = 4.0
            let free = max(0, g.size.width - gaps - minW * Double(shown.count))
            HStack(spacing: 2) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, part in
                    let w = minW + free * Double(part.0) / max(1, total)
                    Group {
                        if part.2 {
                            Hatch(color: palette.unknown).background(palette.unknown.opacity(0.12))
                        } else {
                            Rectangle().fill(part.1 ?? palette.unknown)
                        }
                    }
                    .frame(width: w)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
    }
}

/// A reading against the check's own limit. Unknown is hatched.
struct Meter: View {
    var percent: Double?
    var limit: Double?
    var palette: CardsPalette
    var height = 5.0
    var plain = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                if let p = percent {
                    Capsule().fill(palette.fill)
                    Capsule()
                        .fill(!plain && (limit.map { p > $0 } ?? false) ? palette.warn : palette.accent)
                        .frame(width: max(height, g.size.width * min(100, max(0, p)) / 100))
                } else {
                    Hatch(color: palette.fill, line: 3, gap: 3).clipShape(Capsule())
                }
                if let l = limit, l < 100, percent != nil {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.l2)
                        .frame(width: 1.5, height: height + 4)
                        .offset(x: g.size.width * l / 100 - 0.75)
                }
            }
            .frame(height: g.size.height)
        }
        .frame(height: height)
    }
}

/// A short state word: OPEN, AFFECTED, CACHED.
struct PillView: View {
    var pill: Pill
    var palette: CardsPalette
    var type: CardsType

    var body: some View {
        Text(pill.text)
            .font(type.font(9.5, .bold))
            .tracking(0.45)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(pill.mark == .unknown || pill.mark == .offline ? palette.l2 : palette.color(pill.mark))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(palette.tint(pill.mark)))
    }
}

/// A smoothed series with a soft fill under it.
struct Sparkline: View {
    var values: [Double]
    var top: Double?
    var color: Color

    var body: some View {
        Canvas { ctx, s in
            guard values.count > 1 else { return }
            let peak = top ?? max(1e-9, (values.max() ?? 1) * 1.15)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: Double(i) / Double(values.count - 1) * s.width, y: s.height - 1 - min(1, v / peak) * (s.height - 3))
            }
            var line = Path()
            line.addLines(pts)
            var area = line
            area.addLine(to: CGPoint(x: s.width, y: s.height))
            area.addLine(to: CGPoint(x: 0, y: s.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.32), color.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

/// Lays children out in rows, wrapping as needed.
struct FlowLayout: Layout {
    var spacing = 5.0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x = 0.0, y = 0.0, row = 0.0, widest = 0.0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row = 0.0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

/// A title split at its arrows, the arrows quieter.
func routeText(_ route: [String], arrow: Color) -> AttributedString {
    var out = AttributedString()
    for (i, part) in route.enumerated() {
        if i > 0 {
            var a = AttributedString(" → ")
            a.foregroundColor = arrow
            out += a
        }
        out += AttributedString(part)
    }
    return out
}

/// SF Symbols for this Mac's model.
func macSymbol(_ model: String) -> String {
    let m = model.lowercased()
    if m.contains("mini") { return "macmini" }
    if m.contains("studio") { return "macstudio" }
    if m.contains("imac") { return "desktopcomputer" }
    if m.contains("pro") && !m.contains("book") { return "macpro.gen3" }
    return "laptopcomputer"
}

/// Markdown with its strong runs in `strong`.
func emphasized(_ markdown: String, _ strong: Color) -> AttributedString {
    var a = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    for run in a.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
        a[run.range].foregroundColor = strong
    }
    return a
}

/// Markdown as plain text.
func plain(_ markdown: String) -> String {
    String((try? AttributedString(markdown: markdown))?.characters ?? AttributedString(markdown).characters)
}
