import SwiftUI
import TopophanySections

/// Glance's Status widget: every check on a dial around the verdict's
/// glyph, what needs a look gathered where the dial ends. Beside it or
/// beneath, as Native's: Seen from, and what needs a look or the
/// applications; the extra large adds the map, naming the places that need
/// a look.
struct GlanceWidget: View {
    var model: WidgetModel
    var size: WidgetSize
    var bounds: CGSize
    var ctx: RenderContext

    var p: CardsPalette { CardsPalette.resolve(ctx) }
    var t: CardsType { CardsType(scale: 1, theme: ctx.theme) }
    var status: StatusSection { model.status }
    var vibrant: Bool { ctx.widgetRendering == .vibrant }
    /// Native's widget, for the parts drawn alike.
    var native: CardsWidget { CardsWidget(model: model, size: size, bounds: bounds, ctx: ctx) }

    var body: some View {
        let p = self.p
        let w = WidgetStatus(status: status, p: p, t: t, ctx: ctx)
        Group {
            switch size {
            case .small:
                narrow(w)
            case .medium:
                HStack(alignment: .top, spacing: 16) {
                    narrow(w).frame(width: 136)
                    native.right(p, attentionRows: 3, appRows: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            case .large:
                large(w)
            case .extraLarge:
                HStack(alignment: .top, spacing: 24) {
                    large(w).frame(maxWidth: .infinity, maxHeight: .infinity)
                    places.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(14)
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .foregroundStyle(p.l1)
        .environment(\.colorScheme, ctx.effectiveScheme)
    }

    /// The dial as large as the column leaves it beside the words beneath.
    var dial: Double { min(74, max(48, bounds.height - 28 - 70)) }

    /// The dial, the verdict beneath it, and the foot.
    func narrow(_ w: WidgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    CheckDial(status: status, p: p, vibrant: vibrant).frame(width: dial, height: dial)
                    Spacer(minLength: 0)
                    WidgetMark(palette: p, rendering: ctx.widgetRendering)
                }
                Spacer(minLength: 6)
                Text(status.shortTitle).font(t.font(17, .bold)).tracking(-0.3).lineLimit(1).minimumScaleFactor(0.8)
                // A part given up whole where it doesn't fit: the dial
                // shows how many pass.
                FittedText(parts: status.shortSubtitle).font(t.font(11)).foregroundStyle(p.l2).padding(.top, 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spoken(short: true)))
            Spacer(minLength: 6)
            w.foot(wide: false)
        }
    }

    func large(_ w: WidgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CheckDial(status: status, p: p, vibrant: vibrant).frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title).font(t.font(21, .bold)).tracking(-0.45).lineLimit(1).minimumScaleFactor(0.8)
                    FittedText(parts: status.isBlind ? status.shortSubtitle : status.subtitle)
                        .font(t.font(11.5)).foregroundStyle(p.l2)
                }
                // Clear of the mark in the corner.
                Spacer(minLength: 26)
            }
            .overlay(alignment: .topTrailing) { WidgetMark(palette: p, rendering: ctx.widgetRendering) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spoken(short: false)))
            if let seen = model.panel.seen {
                gap
                WidgetSeen(seen: seen, p: p, t: t)
            }
            gap
            native.right(p, attentionRows: 3, appRows: 6)
            Spacer(minLength: 8)
            w.foot(wide: true)
        }
    }

    /// Between blocks: 12 pt, and up to twice that with room to spare.
    var gap: some View { Spacer(minLength: 12).frame(maxHeight: 24) }

    var hasAttention: Bool { !(model.panel.attention?.items.isEmpty ?? true) }

    /// The extra large's right: the map, naming the places that need a
    /// look, over the applications while something needs attention; Native's
    /// applications and fleet where there's no map.
    @ViewBuilder var places: some View {
        if let m = model.map {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeading(symbol: "map", title: tr("Map"), meta: tr("\(m.places.count) places"), p: p, t: t)
                MapCanvas(map: m, p: p, t: t, detail: .marks, vibrant: vibrant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.sep, lineWidth: 0.5))
                if hasAttention, let apps = model.panel.applications {
                    WidgetApplications(apps: apps, rows: 4, p: p, t: t).padding(.top, 12)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if hasAttention, let apps = model.panel.applications {
                    WidgetApplications(apps: apps, rows: 6, p: p, t: t).padding(.bottom, 12)
                }
                if let fleet = model.panel.fleet { WidgetFleet(fleet: fleet, p: p, t: t) }
            }
        }
    }

    func spoken(short: Bool) -> String {
        let counts = status.isBlind ? nil : status.counts?.complete
        return Words.join([short ? status.shortTitle : status.title, short ? status.shortSubtitle : status.subtitle,
                           counts.map { c in tr("\(c.up) up, \(c.warning) warn, \(c.down) down, \(c.unknown) unknown") } ?? ""])
    }
}

/// Every check on a dial, a tick each, from the top round clockwise: up,
/// then warn, down and unknown, so what needs a look gathers where the dial
/// ends, beside where it began. Unknown ticks are short, so they read apart
/// from the rest without their color. Past what can be told apart, runs of
/// color. While nothing current is known, a dashed ring. The verdict's
/// glyph sits in the middle, on its tint.
struct CheckDial: View {
    var status: StatusSection
    var p: CardsPalette
    var vibrant = false

    var body: some View {
        let hero = HeroSymbol(status: status, size: 0, palette: p)
        let counts = status.isBlind ? nil : status.counts?.complete
        let c = p.color(status.mark)
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            let band = Self.band(d)
            ZStack {
                Circle()
                    .fill(hero.hasColor ? c.opacity(p.isDark ? 0.16 : 0.11) : p.fill2)
                    .padding(band + d * 0.06)
                DialRing(counts: counts, p: p, vibrant: vibrant)
                hero.glyphView.frame(width: d * 0.62, height: d * 0.62)
            }
            .frame(width: d, height: d)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The ring's depth in a dial `d` across.
    static func band(_ d: Double) -> Double { max(5, d * 0.13) }
}

/// The dial's ring (`CheckDial`).
struct DialRing: View {
    var counts: (up: Int, warning: Int, down: Int, unknown: Int)?
    var p: CardsPalette
    var vibrant = false

    struct Run {
        var count: Int
        var color: Color
        var unknown: Bool
    }

    var runs: [Run] {
        guard let n = counts else { return [] }
        // In one tone, weight tells trouble from up, as on the bar.
        return [Run(count: n.up, color: vibrant ? p.l1.opacity(0.3) : p.calmUp, unknown: false),
                Run(count: n.warning, color: vibrant ? p.l1 : p.warn, unknown: false),
                Run(count: n.down, color: vibrant ? p.l1 : p.down, unknown: false),
                Run(count: n.unknown, color: vibrant ? p.l1.opacity(0.6) : p.unknown, unknown: true)]
    }

    var body: some View {
        let runs = self.runs
        let empty = p.unknown.opacity(0.7)
        Canvas { ctx, s in
            let d = min(s.width, s.height)
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let band = CheckDial.band(d)
            let outer = d / 2
            let inner = outer - band
            let mid = (outer + inner) / 2
            func point(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
            let total = runs.reduce(0) { $0 + $1.count }
            guard total > 0 else {
                var ring = Path()
                ring.addEllipse(in: CGRect(x: c.x - mid, y: c.y - mid, width: 2 * mid, height: 2 * mid))
                ctx.stroke(ring, with: .color(empty), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 3]))
                return
            }
            let step = 2 * Double.pi / Double(total)
            // The top, and round clockwise: y runs down.
            let top = -Double.pi / 2
            if mid * step >= 2.4 {
                let width = min(2.4, max(1.2, mid * step * 0.55))
                var k = 0
                for run in runs {
                    var path = Path()
                    for _ in 0..<run.count {
                        let a = top + (Double(k) + 0.5) * step
                        path.move(to: point(run.unknown ? inner + band * 0.5 : inner, a))
                        path.addLine(to: point(outer, a))
                        k += 1
                    }
                    ctx.stroke(path, with: .color(run.color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                }
            } else {
                // Runs a hair apart, each at least a tick's width.
                let gap = min(0.05, step)
                var a = top
                for run in runs where run.count > 0 {
                    let sweep = step * Double(run.count)
                    let from = a + gap / 2, to = max(from + 0.02, a + sweep - gap / 2)
                    let n = max(2, Int((to - from) / 0.03))
                    var arc = Path()
                    arc.addLines((0...n).map { point(run.unknown ? inner + band * 0.75 : mid, from + (to - from) * Double($0) / Double(n)) })
                    ctx.stroke(arc, with: .color(run.color), style: StrokeStyle(lineWidth: run.unknown ? band * 0.5 : band, lineCap: .butt))
                    a += sweep
                }
            }
        }
    }
}
