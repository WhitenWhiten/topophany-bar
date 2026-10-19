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
    /// Increase Contrast: drawn things take more ink.
    var increaseContrast = false
    /// Where a night surface deepens to, at the foot.
    var panel2: Color?
    /// A texture's ink.
    var grain = Color.clear
    var style = CardsStyle()

    static func resolve(_ ctx: RenderContext) -> CardsPalette {
        let dark = ctx.effectiveScheme == .dark
        let hc = ctx.increaseContrast
        func token(_ slot: String) -> Color? { ctx.theme.color(slot, dark: dark).map(Color.init) }
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
        p.increaseContrast = hc
        p.style = CardsStyle(ctx.theme)
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
        // A matte or night ground is opaque already; glass gives way to a
        // solid fill under Reduce Transparency.
        if let c = token("panelMaterial"), !ctx.reduceTransparency || p.style.surface != .glass { p.panel = c }
        p.panel2 = token("panelMaterial2")
        if let c = token("grain") { p.grain = c.opacity(hc ? 0.5 : 1) }
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

/// Eases a change in `value` into place, as a new frame changes it; still
/// under Reduce Motion.
struct Settle<V: Equatable>: ViewModifier {
    var value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .smooth(duration: 0.45), value: value)
    }
}

extension View {
    func settles<V: Equatable>(on value: V) -> some View { modifier(Settle(value: value)) }
}

/// The text sizes of the cards renderer, scaled by the Text size setting,
/// in the theme's family.
struct CardsType {
    var scale: Double
    var design: Font.Design = .default

    init(scale: Double, theme: Theme? = nil) {
        self.scale = scale
        design = switch theme?.font?.family {
        case "SF Pro Rounded": .rounded
        case "New York": .serif
        default: .default
        }
    }

    func font(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight, design: design)
    }

    func mono(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight, design: design).monospacedDigit()
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
        Canvas { ctx, s in Self.draw(mark, in: ctx, size: s.width, color: color, on: on) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// Draws `mark` in a `size`-point square at the context's origin.
    nonisolated static func draw(_ mark: Mark, in ctx: GraphicsContext, size: Double, color: Color, on: Color = .white) {
        var ctx = ctx
        let k = size / 14
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
}

/// The Status card's symbol: a flat tile tinted with the verdict's color,
/// edged in it, and its glyph in the color itself. Calm enough to sit
/// beside for hours; the glyph's shape says the state on its own.
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

    var hasColor: Bool { status.mark == .up || status.mark == .degraded || status.mark == .down }

    /// The glyph: the status color, a shade deeper on light so it holds on
    /// its tint; the secondary ink for unknown and offline.
    var ink: Color {
        guard hasColor else { return palette.l2 }
        let c = palette.color(status.mark)
        return palette.isDark ? c : c.mix(with: .black, by: 0.12)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: palette.style.heroRadius(size), style: .continuous)
        let c = palette.color(status.mark)
        let hc = palette.increaseContrast
        shape
            .fill(hasColor ? c.opacity((palette.isDark ? 0.2 : 0.15) + (hc ? 0.1 : 0)) : palette.fill2)
            .overlay(shape.strokeBorder(hasColor ? c.opacity(hc ? 0.6 : 0.3) : palette.sep, lineWidth: hc ? 1 : 0.75))
            .overlay { glyphView }
            .frame(width: size, height: size)
            .settles(on: status.mark)
            .accessibilityHidden(true)
    }

    var glyphView: some View {
        Canvas { ctx, s in
            let k = s.width / 47
            ctx.scaleBy(x: k, y: k)
            let shade = GraphicsContext.Shading.color(ink)
            func stroke(_ p: Path, _ w: Double) {
                ctx.stroke(p, with: shade, style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
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
                ctx.fill(Path(ellipseIn: CGRect(x: 21.2, y: 29.3, width: 4.6, height: 4.6)), with: shade)
            case .cross:
                p.move(to: CGPoint(x: 16.5, y: 16.5))
                p.addLine(to: CGPoint(x: 30.5, y: 30.5))
                p.move(to: CGPoint(x: 30.5, y: 16.5))
                p.addLine(to: CGPoint(x: 16.5, y: 30.5))
                stroke(p, 3.6)
            case .dots:
                for x in [15.5, 23.5, 31.5] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.4, y: 21.1, width: 4.8, height: 4.8)), with: shade)
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
            // Up is quieter than trouble, so what needs a look stands out:
            // as quiet as the widgets' marks for up.
            draw(c.up) { ctx.fill(Path(roundedRect: $0, cornerRadius: r), with: .color(p.up.opacity(p.increaseContrast ? 0.75 : 0.55))) }
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

/// A reading against the check's own limit, in the theme's meter: past
/// the limit it reads in the warning color. Unknown is hatched, never
/// empty.
struct Meter: View {
    var percent: Double?
    var limit: Double?
    var palette: CardsPalette
    var height = 5.0
    var plain = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = palette
        let style = p.style.meter
        // Eases from the reading before; Canvas draws what the animation
        // says it is now.
        MeterCanvas(value: (percent ?? 0) / 100) { ctx, s, v in
            guard percent != nil else {
                style.drawUnknown(ctx, size: s, color: p.fill)
                return
            }
            let over = !plain ? limit.map { $0 / 100 } : nil
            var parts = [MeterStyle.Part(end: min(v, over ?? 1), color: p.accent)]
            if let over, v > over { parts.append(.init(end: min(1, v), color: p.warn)) }
            style.draw(ctx, size: s, parts: parts, track: p.fill, limit: percent == nil ? nil : limit, ink: p.l2, scale: p.l3)
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: percent)
    }
}

/// A meter's canvas, its value animatable, reaching past its frame by the
/// limit mark's overhang.
struct MeterCanvas: View, @MainActor Animatable {
    var value: Double
    var draw: (GraphicsContext, CGSize, Double) -> Void

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let o = MeterStyle.overhang
        GeometryReader { g in
            Canvas { ctx, s in
                var c = ctx
                c.translateBy(x: 0, y: o)
                draw(c, CGSize(width: s.width, height: s.height - 2 * o), value)
            }
            .frame(width: g.size.width, height: g.size.height + 2 * o)
            .offset(y: -o)
        }
    }
}

/// A short state word: OPEN, AFFECTED, CACHED. Plain, it's the word alone
/// in its color, for rows whose mark already says the state.
struct PillView: View {
    var pill: Pill
    var palette: CardsPalette
    var type: CardsType
    var plain = false

    var body: some View {
        Text(pill.text)
            .font(type.font(9.5, .bold))
            .tracking(plain ? 0.6 : 0.45)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(pill.mark == .unknown || pill.mark == .offline ? palette.l2 : palette.color(pill.mark))
            .padding(.horizontal, plain ? 0 : 6)
            .padding(.vertical, 2)
            .background {
                if !plain {
                    RoundedRectangle(cornerRadius: palette.style.chip(5), style: .continuous).fill(palette.tint(pill.mark))
                }
            }
    }
}

/// A history as bars, newest at the right, over a baseline, in the
/// theme's meter; before the history is full, the left is baseline only.
struct BarHistory: View {
    var values: [Double]
    /// The value a full bar stands for.
    var top: Double
    var capacity: Int
    var color: Color
    var baseline: Color
    var style = MeterStyle.ticks

    var body: some View {
        Canvas { ctx, s in
            style.drawHistory(ctx, size: s, values: values, top: top, capacity: capacity, color: color, baseline: baseline)
        }
    }
}

/// Two histories on one axis: `up` above the line, `down` below it, on a
/// shared scale.
struct MirrorChart: View {
    var up: [Double]
    var down: [Double]
    var upColor: Color
    var downColor: Color
    var axis: Color

    var body: some View {
        Canvas { ctx, s in
            let mid = (s.height / 2).rounded()
            let peak = max(1e-9, (up + down).max() ?? 0) * 1.1
            func area(_ values: [Double], _ sign: Double) -> (Path, Path) {
                let pts = values.enumerated().map { i, v in
                    CGPoint(x: Double(i) / Double(max(1, values.count - 1)) * s.width, y: mid - sign * min(1, v / peak) * (mid - 1))
                }
                var line = Path()
                line.addLines(pts)
                var fill = line
                fill.addLine(to: CGPoint(x: s.width, y: mid))
                fill.addLine(to: CGPoint(x: 0, y: mid))
                fill.closeSubpath()
                return (line, fill)
            }
            for (values, sign, color) in [(up, 1.0, upColor), (down, -1.0, downColor)] where values.count > 1 {
                let (line, fill) = area(values, sign)
                ctx.fill(fill, with: .color(color.opacity(0.26)))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.25, width: s.width, height: 0.5)), with: .color(axis))
        }
    }
}

/// Parts of a whole in one meter, each its share of `total`, in the
/// theme's meter; what is left is the track.
struct PartsBar: View {
    var parts: [(Double, Color)]
    var total: Double
    var track: Color
    var height = 7.0
    var style = MeterStyle.ticks
    var scale = Color.clear

    var body: some View {
        let parts = self.parts, total = self.total
        MeterCanvas(value: 0) { ctx, s, _ in
            var end = 0.0
            let shares = parts.filter { $0.0 > 0 }.map { v, color in
                end = min(1, end + v / max(total, 1e-9))
                return MeterStyle.Part(end: end, color: color)
            }
            style.draw(ctx, size: s, parts: shares, track: track, limit: nil, ink: .clear, scale: scale)
        }
        .frame(height: height)
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

/// A title split at its arrows, the arrows quieter, on one line. When it
/// doesn't fit, the longest parts give up room first, so both ends stay
/// readable: "Primary Bandwag… → Oracle Exit A".
struct RouteLine: View {
    var route: [String]
    var arrow: Color

    var body: some View {
        RouteLayout(spacing: 3.5) {
            ForEach(Array(route.enumerated()), id: \.offset) { i, part in
                if i > 0 {
                    Text(verbatim: "→").foregroundStyle(arrow).layoutValue(key: RouteLayout.Fixed.self, value: true)
                }
                Text(part)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(route.joined(separator: " → ")))
    }
}

/// Parts in a line at their own widths while they fit. When they don't,
/// fixed parts keep theirs and the rest share what's left: a part that
/// fits an equal share keeps its width, and longer ones split the rest.
struct RouteLayout: Layout {
    var spacing: CGFloat

    struct Fixed: LayoutValueKey { static let defaultValue = false }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(proposal.width, subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: widths.reduce(0, +) + gaps(subviews), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (v, w) in zip(subviews, widths(bounds.width, subviews)) {
            v.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }

    func gaps(_ subviews: Subviews) -> CGFloat { spacing * CGFloat(max(0, subviews.count - 1)) }

    func widths(_ available: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let available, ideal.reduce(0, +) + gaps(subviews) > available else { return ideal }
        var out = ideal
        let shared = subviews.indices.filter { !subviews[$0][Fixed.self] }.sorted { ideal[$0] < ideal[$1] }
        var room = available - gaps(subviews) - subviews.indices.filter { subviews[$0][Fixed.self] }.reduce(0) { $0 + ideal[$1] }
        var left = shared.count
        for i in shared {
            out[i] = min(ideal[i], max(0, room) / CGFloat(left))
            room -= out[i]
            left -= 1
        }
        // A cut part ends at a whole letter, short of its share: what it
        // leaves goes to the next part that was cut, shortest first.
        for i in shared where out[i] < ideal[i] {
            let used = min(out[i], subviews[i].sizeThatFits(ProposedViewSize(width: out[i], height: nil)).width)
            room += out[i] - used
            out[i] = used
        }
        for i in shared where out[i] < ideal[i] && room > 0.5 {
            let more = min(ideal[i], out[i] + room)
            let used = min(more, subviews[i].sizeThatFits(ProposedViewSize(width: more, height: nil)).width)
            room -= used - out[i]
            out[i] = used
        }
        return out
    }
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
