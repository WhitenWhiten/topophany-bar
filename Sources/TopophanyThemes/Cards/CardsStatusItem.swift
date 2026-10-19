import SwiftUI
import TopophanySections

/// The menu bar item: a globe with the status badge cut into its corner,
/// and the count or words beside it. This Mac's readings, when shown, come
/// before it as a part of their own.
///
/// It moves only to say something. The globe turns while what it shows is
/// current and comes to rest when nothing current is known; the badge's
/// dashed ring turns while `topo` starts. A change swaps the badge and rolls
/// the words, and one that needs more attention sends out a ripple.
struct CardsStatusItem: View {
    var model: StatusItemModel
    var ctx: StatusItemContext

    /// Meridians around the globe. At rest two stand either side of the
    /// middle, the globe of the still item.
    static let meridians = 7
    static let badgeCenter = CGPoint(x: 14.6, y: 14.6)

    /// The front half of a meridian on a unit globe, top to bottom.
    static let meridian: Path = {
        let k = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -1))
        p.addCurve(to: CGPoint(x: 1, y: 0), control1: CGPoint(x: k, y: -1), control2: CGPoint(x: 1, y: -k))
        p.addCurve(to: CGPoint(x: 0, y: 1), control1: CGPoint(x: 1, y: k), control2: CGPoint(x: k, y: 1))
        return p
    }()

    var ink: Color { ctx.menuBarIsDark ? .white : Color(white: 0.08) }

    func color(_ mark: Mark) -> Color {
        guard model.statusColors else { return ink }
        switch mark {
        case .up: return ctx.menuBarIsDark ? Color(rgb: 0x32D74B) : Color(rgb: 0x28B449)
        case .degraded: return ctx.menuBarIsDark ? Color(rgb: 0xFF9F0A) : Color(rgb: 0xF08C00)
        case .down: return ctx.menuBarIsDark ? Color(rgb: 0xFF453A) : Color(rgb: 0xFF3B30)
        case .unknown, .offline: return ink
        }
    }

    /// The latest change, while it settles.
    var change: StatusItemMotion.Change? {
        guard ctx.motion.moves, let c = ctx.motion.change, c.age < StatusItemMotion.changeLength else { return nil }
        return c
    }

    var body: some View {
        HStack(spacing: 0) {
            Canvas { c, size in
                drawGlobe(&c, size)
                drawBadge(&c)
            }
            .frame(width: 19, height: 19)
            .overlay { ripple }
            words
        }
        .padding(.horizontal, 1)
        .frame(height: 22)
    }

    // MARK: globe

    func drawGlobe(_ c: inout GraphicsContext, _ size: CGSize) {
        // The globe, with room cut out for the badge.
        var globe = c
        globe.clipToLayer { mask in
            mask.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            mask.blendMode = .clear
            mask.fill(Path(ellipseIn: CGRect(x: Self.badgeCenter.x - 5.1, y: Self.badgeCenter.y - 5.1, width: 10.2, height: 10.2)),
                      with: .color(.white))
        }
        let style = StrokeStyle(lineWidth: 1.45, lineCap: .round)
        var rim = Path()
        rim.addEllipse(in: CGRect(x: 2, y: 2, width: 14, height: 14))
        rim.move(to: CGPoint(x: 2, y: 9))
        rim.addLine(to: CGPoint(x: 16, y: 9))
        globe.stroke(rim, with: .color(ink), style: style)
        // Meridians come round from the left and fade toward the rim.
        let step = 2 * Double.pi / Double(Self.meridians)
        for k in 0..<Self.meridians {
            let longitude = (ctx.motion.turn + 0.5 + Double(k)) * step
            let a = Ease.step(0.5, 0.9, cos(longitude))
            guard a > 0.004 else { continue }
            let t = CGAffineTransform(translationX: 9, y: 9).scaledBy(x: 7 * sin(longitude), y: 7)
            globe.stroke(Self.meridian.applying(t), with: .color(ink.opacity(a)), style: style)
        }
    }

    // MARK: badge

    func drawBadge(_ c: inout GraphicsContext) {
        guard let ch = change else { return badge(&c, model.mark, scale: 1) }
        if ch.from.mark != model.mark {
            // The old badge shrinks away and the new one settles in.
            let out = 1 - Ease.in(Ease.span(ch.age, 0, 0.16))
            if out > 0 { badge(&c, ch.from.mark, scale: out) }
            let into = Ease.back(Ease.span(ch.age, 0.08, 0.42))
            if into > 0 { badge(&c, model.mark, scale: into) }
        } else if model.needsMoreAttention(than: ch.from) {
            // More of the same: one beat.
            badge(&c, model.mark, scale: 1 + 0.24 * sin(.pi * Ease.span(ch.age, 0, 0.34)))
        } else {
            badge(&c, model.mark, scale: 1)
        }
    }

    func badge(_ c: inout GraphicsContext, _ mark: Mark, scale: Double) {
        var g = c
        let o = Self.badgeCenter
        if scale != 1 {
            g.translateBy(x: o.x, y: o.y)
            g.scaleBy(x: scale, y: scale)
            g.translateBy(x: -o.x, y: -o.y)
        }
        let b = color(mark)
        switch mark {
        case .up:
            g.fill(Path(ellipseIn: CGRect(x: o.x - 3.3, y: o.y - 3.3, width: 6.6, height: 6.6)), with: .color(b))
        case .degraded:
            var t = Path()
            t.move(to: CGPoint(x: o.x, y: o.y - 3.7))
            t.addLine(to: CGPoint(x: o.x + 3.7, y: o.y + 2.8))
            t.addLine(to: CGPoint(x: o.x - 3.7, y: o.y + 2.8))
            t.closeSubpath()
            g.fill(t, with: .color(b))
            g.stroke(t, with: .color(b), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
        case .down:
            g.clipToLayer { mask in
                mask.fill(Path(roundedRect: CGRect(x: o.x - 3.5, y: o.y - 3.5, width: 7, height: 7), cornerRadius: 1.6), with: .color(.white))
                mask.blendMode = .clear
                var cross = Path()
                cross.move(to: CGPoint(x: o.x - 1.5, y: o.y - 1.5))
                cross.addLine(to: CGPoint(x: o.x + 1.5, y: o.y + 1.5))
                cross.move(to: CGPoint(x: o.x + 1.5, y: o.y - 1.5))
                cross.addLine(to: CGPoint(x: o.x - 1.5, y: o.y + 1.5))
                mask.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: 1.15, lineCap: .round))
            }
            g.fill(Path(CGRect(x: o.x - 4.6, y: o.y - 4.6, width: 9.2, height: 9.2)), with: .color(b))
        case .unknown:
            g.stroke(Path(ellipseIn: CGRect(x: o.x - 2.7, y: o.y - 2.7, width: 5.4, height: 5.4)), with: .color(b), lineWidth: 1.3)
        case .offline:
            // Seven dashes all the way round, so it can turn without a seam;
            // it turns while `topo` starts.
            if model.activity == .connecting, ctx.motion.moves {
                g.translateBy(x: o.x, y: o.y)
                g.rotate(by: .radians(ctx.motion.time * 2 * .pi / 2.4))
                g.translateBy(x: -o.x, y: -o.y)
            }
            let dash = 2 * Double.pi * 2.7 / 7
            g.stroke(Path(ellipseIn: CGRect(x: o.x - 2.7, y: o.y - 2.7, width: 5.4, height: 5.4)), with: .color(b),
                     style: StrokeStyle(lineWidth: 1.3, dash: [1.3, dash - 1.3]))
        }
    }

    /// One ring out from the badge when a change needs more attention.
    @ViewBuilder var ripple: some View {
        if let ch = change, model.needsMoreAttention(than: ch.from) {
            let t = Ease.span(ch.age, 0, StatusItemMotion.changeLength)
            Canvas { c, _ in
                let r = 3.6 + 6.4 * Ease.out(t)
                let o = CGPoint(x: Self.badgeCenter.x + 8, y: Self.badgeCenter.y + 8)
                c.stroke(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(color(model.mark).opacity(0.75 * pow(1 - t, 1.6))), lineWidth: 1.4 - 0.6 * t)
            }
            .frame(width: 35, height: 35)
        }
    }

    // MARK: words

    /// The count or words. A change rolls them: up for more, down for less.
    @ViewBuilder var words: some View {
        if let ch = change, ch.from.text != model.text {
            let up = model.needsMoreAttention(than: ch.from) || (model.count ?? 0) > (ch.from.count ?? 0)
            let d = up ? 7.0 : -7.0
            RollLayout(progress: Ease.inOut(Ease.span(ch.age, 0, 0.4))) {
                label(ch.from.text)
                    .offset(y: -d * Ease.in(Ease.span(ch.age, 0, 0.28)))
                    .opacity(1 - Ease.span(ch.age, 0, 0.22))
                label(model.text)
                    .offset(y: d * (1 - Ease.out(Ease.span(ch.age, 0.06, 0.34))))
                    .opacity(Ease.span(ch.age, 0.06, 0.24))
            }
        } else {
            label(model.text)
        }
    }

    @ViewBuilder func label(_ text: String) -> some View {
        if text.isEmpty {
            Color.clear.frame(width: 0, height: 0)
        } else {
            Text(text)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .tracking(-0.13)
                .foregroundStyle(ink)
                .fixedSize()
                .padding(.leading, 5)
        }
    }
}

/// Two views in one place, as wide as the first going on to as wide as the
/// second, so a roll widens or narrows the item smoothly.
struct RollLayout: Layout {
    var progress: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard let first = sizes.first, let last = sizes.last else { return .zero }
        return CGSize(width: first.width + (last.width - first.width) * progress, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for v in subviews {
            v.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(v.sizeThatFits(.unspecified)))
        }
    }
}

/// This Mac's readings in the menu bar's ink, as tall as the item.
struct CardsMenuReadings: View {
    var readings: [MenuBarReading]
    var ink: Color

    var body: some View {
        HStack(spacing: 9) {
            ForEach(readings) { CardsMenuReading(reading: $0, ink: ink) }
        }
        .padding(.horizontal, 1)
        .frame(height: 22)
    }
}

/// One of this Mac's readings in the menu bar's ink, as wide as its widest
/// value so the item holds still: CPU as bars, the newest brightest; memory
/// as a ring; network as what goes up over what comes down, each against
/// its arrow.
struct CardsMenuReading: View {
    var reading: MenuBarReading
    var ink: Color

    static let valueFont = Font.system(size: 11.5, weight: .medium).monospacedDigit()
    static let rateFont = Font.system(size: 8.6, weight: .medium).monospacedDigit()

    var body: some View {
        Group {
            switch reading.kind {
            case .cpu:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    MenuBarBars(history: reading.history, ink: ink)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    value
                }
            case .memory:
                HStack(spacing: 4) {
                    MenuBarRing(fraction: reading.fraction, ink: ink)
                    value
                }
            case .network:
                HStack(spacing: 2) {
                    ZStack(alignment: .trailing) {
                        Text(MenuBarReading.widestRate).hidden()
                        VStack(alignment: .trailing, spacing: -1) {
                            Text(reading.sentText)
                            Text(reading.receivedText)
                        }
                    }
                    .font(Self.rateFont)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
                    VStack(spacing: 0) {
                        arrow("arrow.up")
                        arrow("arrow.down")
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(reading.spoken))
    }

    var value: some View {
        ZStack(alignment: .leading) {
            Text(MenuBarReading.widestPercent).hidden()
            Text(reading.value).foregroundStyle(ink)
        }
        .font(Self.valueFont)
        .lineLimit(1)
        .fixedSize()
    }

    func arrow(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 6.6, weight: .bold))
            .foregroundStyle(ink.opacity(0.55))
            .frame(height: 9.4)
    }
}

/// CPU over the latest samples, oldest first: one bar each, older ones
/// fainter. A bar never drops below a dot, so idle reads as a dotted line.
struct MenuBarBars: View {
    var history: [Double]
    var ink: Color

    static let count = 10
    static let bar = 1.5
    static let gap = 0.9
    static let height = 11.5

    var body: some View {
        Canvas { c, size in
            let h = history.suffix(Self.count)
            for (i, v) in h.enumerated() {
                let x = Double(Self.count - h.count + i) * (Self.bar + Self.gap)
                let height = max(Self.bar, min(1, max(0, v)) * size.height)
                let age = Double(h.count - 1 - i) / Double(Self.count - 1)
                c.fill(Path(roundedRect: CGRect(x: x, y: size.height - height, width: Self.bar, height: height), cornerRadius: Self.bar / 2),
                       with: .color(ink.opacity(1 - 0.6 * age)))
            }
        }
        .frame(width: Double(Self.count) * (Self.bar + Self.gap) - Self.gap, height: Self.height)
    }
}

/// Memory in use as a ring from twelve o'clock; just the track while
/// nothing is known.
struct MenuBarRing: View {
    var fraction: Double?
    var ink: Color

    var body: some View {
        Canvas { c, size in
            let line = 2.0
            let r = CGRect(origin: .zero, size: size).insetBy(dx: line / 2, dy: line / 2)
            c.stroke(Path(ellipseIn: r), with: .color(ink.opacity(0.26)), lineWidth: line)
            if let f = fraction, f > 0 {
                var arc = Path()
                arc.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * min(1, f)), clockwise: false)
                c.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
            }
        }
        .frame(width: 12.5, height: 12.5)
    }
}
