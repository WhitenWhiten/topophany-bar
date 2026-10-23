import Foundation
import SwiftUI
import TopophanySections

/// The Native widgets: the panel's cards, cut to a widget's size
/// (DESIGN.md §7.1).
struct CardsWidget: View {
    var model: WidgetModel
    var size: WidgetSize
    var bounds: CGSize
    var ctx: RenderContext

    var p: CardsPalette { CardsPalette.resolve(ctx) }
    var t: CardsType { CardsType(scale: 1, theme: ctx.theme) }

    var body: some View {
        let p = self.p
        Group {
            switch model.kind {
            case .status: status(p)
            case .server: server(p)
            case .service: service(p)
            case .zones:
                if let z = model.zones {
                    WidgetZones(zones: z, size: size, room: CGSize(width: bounds.width - 28, height: bounds.height - 28),
                                p: p, t: t, rendering: ctx.widgetRendering)
                }
            case .map:
                WidgetMap(model: model, size: size, p: p, t: t, ctx: ctx).padding(-14)
            }
        }
        .padding(14)
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .foregroundStyle(p.l1)
        .environment(\.colorScheme, ctx.effectiveScheme)
    }

    // MARK: Status

    @ViewBuilder func status(_ p: CardsPalette) -> some View {
        if let sources = model.status.sources {
            WidgetSources(model: model, sources: sources, size: size, p: p, t: t, ctx: ctx)
        } else {
            let w = WidgetStatus(status: model.status, p: p, t: t, ctx: ctx)
            switch size {
            case .small:
                narrow(w)
            case .medium:
                HStack(alignment: .top, spacing: 16) {
                    narrow(w).frame(width: 136)
                    right(p, attentionRows: 3, appRows: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            case .large:
                large(p, w, appRows: 6)
            case .extraLarge:
                HStack(alignment: .top, spacing: 24) {
                    large(p, w, appRows: 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 0) {
                        if hasAttention, let apps = model.panel.applications {
                            WidgetApplications(apps: apps, rows: 6, p: p, t: t).padding(.bottom, 12)
                        }
                        if let fleet = model.panel.fleet {
                            WidgetFleet(fleet: fleet, p: p, t: t)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// The verdict in a narrow column: the checks fill the room between
    /// its words and the foot.
    func narrow(_ w: WidgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            w.compact
            w.checks.padding(.bottom, 8).layoutPriority(1)
            Spacer(minLength: 0)
            w.foot(wide: false)
        }
    }

    var hasAttention: Bool { !(model.panel.attention?.items.isEmpty ?? true) }

    func large(_ p: CardsPalette, _ w: WidgetStatus, appRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            w.big
            if let seen = model.panel.seen {
                gap
                WidgetSeen(seen: seen, p: p, t: t)
            }
            gap
            right(p, attentionRows: 3, appRows: appRows)
            Spacer(minLength: 8)
            w.foot(wide: true)
        }
    }

    /// Between blocks: 12 pt, and up to twice that when the widget has room
    /// to spare, so what's left spreads out instead of pooling above the
    /// foot.
    var gap: some View { Spacer(minLength: 12).frame(maxHeight: 24) }

    /// Needs attention, or Applications when nothing needs attention, as
    /// the medium widget's Right choice says.
    @ViewBuilder func right(_ p: CardsPalette, attentionRows: Int, appRows: Int) -> some View {
        let attention = model.panel.attention.flatMap { $0.items.isEmpty ? nil : $0 }
        let apps = model.panel.applications
        switch (model.right, attention, apps) {
        case (.applications, _, let a?), (.automatic, nil, let a?):
            WidgetApplications(apps: a, rows: appRows, p: p, t: t)
        case (_, let a?, _):
            WidgetAttention(attention: a, rows: attentionRows, p: p, t: t)
        default:
            WidgetEmpty(status: model.status, p: p, t: t)
        }
    }

    // MARK: Server

    @ViewBuilder func server(_ p: CardsPalette) -> some View {
        let card = model.server ?? placeholder
        let left = WidgetServerCard(card: card, isMac: isMac, p: p, t: t, ctx: ctx)
        if size == .small {
            left
        } else if card.origin != nil, card.services.isEmpty, card.observes.isEmpty {
            // A server read from a source has no services to list: its
            // meters take the width, with what each measures.
            WidgetServerCard(card: card, isMac: isMac, p: p, t: t, ctx: ctx, sizes: true)
        } else {
            HStack(alignment: .top, spacing: 16) {
                left.frame(width: 136)
                WidgetServices(card: card, p: p, t: t)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    var isMac: Bool { if case .server(_, true) = model.kind { true } else { false } }

    // MARK: Service

    @ViewBuilder func service(_ p: CardsPalette) -> some View {
        let card = model.service ?? servicePlaceholder
        let left = WidgetServiceCard(card: card, p: p, t: t, ctx: ctx)
        if size == .small {
            left
        } else {
            HStack(alignment: .top, spacing: 16) {
                left.frame(width: 136)
                WidgetServiceReach(card: card, p: p, t: t)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// A service whose card hasn't arrived: its ID, and nothing else known.
    var servicePlaceholder: ServiceCardModel {
        let id = if case .service(let s) = model.kind { s } else { "" }
        return ServiceCardModel(id: id, name: id.isEmpty ? tr("No service chosen") : id, application: "",
                                host: .init(name: "", kind: "", provider: ""), hostMark: .offline, mark: .offline,
                                pill: .cached, isWithheld: true, isMissing: true, observers: [], checks: [],
                                placeholder: id.isEmpty ? tr("Choose one in Edit Widget") : tr("Not received yet"),
                                sampledAt: nil, now: model.status.now)
    }

    /// A node whose card hasn't arrived: its ID, and nothing else known.
    var placeholder: ServerCardModel {
        let node = if case .server(let n, _) = model.kind { n } else { "" }
        let none = ServerCardModel.Meter(percent: nil, limit: nil, detail: "")
        return ServerCardModel(id: node, name: node.isEmpty ? tr("No server chosen") : node, kind: "", provider: "",
                               place: node.isEmpty ? tr("Choose one in Edit Widget") : tr("Not received yet"),
                               mark: .offline, pill: .cached, isWithheld: true, isMissing: true, cpu: none, memory: none,
                               disk: none, services: [], servicesSummary: "", observes: [], sampledAt: nil,
                               now: model.status.now)
    }
}

/// How old something is: counting up on its own in a widget, fixed in a
/// snapshot.
struct Age: View {
    var date: Date
    var now: Date
    var live: Bool
    var compact = false

    var body: some View {
        if live {
            Text(.currentDate, format: .reference(to: date, allowedFields: [.minute, .hour, .day], maxFieldCount: 1))
        } else {
            Text(Words.ago(date, now: now, style: compact ? .compact : .spaced))
        }
    }
}

/// The brand mark in a widget's corner: small and a little muted, so it
/// says whose widget it is without competing with the verdict. Where the
/// desktop draws widgets in one tone, it would flatten the mark into a
/// disc that reads as a status mark, so there the globe is its lines.
struct WidgetMark: View {
    var palette: CardsPalette
    var rendering = RenderContext.WidgetRendering.fullColor

    var body: some View {
        if rendering == .fullColor {
            BrandMark().frame(width: 16, height: 16).saturation(0.75).opacity(0.9).padding(1)
        } else {
            GlobeLines().stroke(palette.l2, style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                .frame(width: 14, height: 14).padding(2)
                .accessibilityHidden(true)
        }
    }
}

/// The menu bar item's globe at rest, as lines: its rim, its equator, and
/// the two meridians either side of the middle.
struct GlobeLines: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        p.move(to: CGPoint(x: c.x - r, y: c.y))
        p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        // At rest the item's two meridians stand half a seventh of a turn
        // either side of the middle: sin(π / 7) of the radius out.
        let w = r * sin(.pi / 7)
        p.addEllipse(in: CGRect(x: c.x - w, y: c.y - r, width: 2 * w, height: 2 * r))
        return p
    }
}

/// The verdict block, small and large.
@MainActor
struct WidgetStatus {
    var status: StatusSection
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext

    var compact: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                HeroSymbol(status: status, size: 34, palette: p)
                Spacer(minLength: 0)
                WidgetMark(palette: p, rendering: ctx.widgetRendering)
            }
            Text(status.shortTitle).font(t.font(16, .semibold)).tracking(-0.24).lineLimit(1)
                .padding(.top, 10)
            Text(status.shortSubtitle).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1)
                .padding(.top, 2).padding(.bottom, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.join([status.title, status.shortSubtitle])))
    }

    /// Every check in the room it's given, a mark each; withheld while
    /// blind.
    @ViewBuilder var checks: some View {
        if !status.isBlind, let c = status.counts?.complete {
            CheckGrid(counts: c, palette: p, vibrant: ctx.widgetRendering == .vibrant)
                .frame(maxHeight: 34)
                .accessibilityHidden(true)
        } else {
            bar
        }
    }

    var big: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HeroSymbol(status: status, size: 44, palette: p)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title).font(t.font(18, .semibold)).tracking(-0.27).lineLimit(1)
                    Text(status.isBlind ? status.shortSubtitle : status.subtitle)
                        .font(t.font(11)).foregroundStyle(p.l2).lineLimit(1)
                }
                Spacer(minLength: 0)
                WidgetMark(palette: p, rendering: ctx.widgetRendering)
            }
            .accessibilityElement(children: .combine)
            bar.padding(.top, 12).padding(.bottom, 7)
            if !status.isBlind, let c = status.counts?.complete { legend(c) }
        }
    }

    @ViewBuilder var bar: some View {
        if !status.isBlind, let c = status.counts?.complete {
            StackBar(counts: c, palette: p, vibrant: ctx.widgetRendering == .vibrant)
        } else {
            Hatch(color: p.fill, line: 3, gap: 3)
                .frame(height: 6)
                .clipShape(Capsule())
                .frame(height: StackBar.tickHeight)
        }
    }

    func legend(_ c: (up: Int, warning: Int, down: Int, unknown: Int)) -> some View {
        HStack(spacing: 13) {
            item(c.up, .up, tr("up"))
            item(c.warning, .degraded, tr("warn"))
            item(c.down, .down, tr("down"))
            item(c.unknown, .unknown, tr("unknown"))
        }
        .font(t.font(11)).foregroundStyle(p.l2)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tr("\(c.up) up, \(c.warning) warn, \(c.down) down, \(c.unknown) unknown")))
    }

    func item(_ n: Int, _ m: Mark, _ word: String) -> some View {
        HStack(spacing: 4) {
            // A count of none takes no color: its shape says which it is.
            CardMark(mark: m, size: 9, color: n == 0 ? p.l3 : p.listColor(m))
            Text("\(n)").font(t.mono(11, .semibold)).foregroundStyle(n == 0 ? p.l3 : p.l1)
            Text(word).foregroundStyle(n == 0 ? p.l3 : p.l2)
        }
    }

    /// Observers live and the age, at the bottom.
    func foot(wide: Bool) -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "target").font(.system(size: 10))
                if !status.isBlind, let live = status.observersLive, let all = status.observersAll {
                    Text(wide ? tr("\(live)/\(all) observers live") : "\(live)/\(all)")
                } else {
                    Text(wide ? tr("Observers not known now") : "—")
                }
            }
            Spacer(minLength: 4)
            if let at = status.isBlind ? status.lastKnown?.at ?? status.updatedAt : status.updatedAt {
                Age(date: at, now: status.now, live: ctx.liveDates)
            }
        }
        .font(t.font(10.5)).foregroundStyle(p.l3)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The panel's ticks, wrapped into a grid for a narrow column: every
/// check as its mark, filled a column at a time in the bar's order (up,
/// warn, down, unknown), so trouble gathers at the right as it does on the
/// bar. Up is quieter than trouble. Past what can be told apart, the
/// stacked bar.
struct CheckGrid: View {
    var counts: (up: Int, warning: Int, down: Int, unknown: Int)
    var palette: CardsPalette
    /// Monochrome keeps shape and weight only, so up is quieter still.
    var vibrant = false

    struct Cells: Equatable {
        var rows: Int
        var columns: Int
        var width: Double
        /// A mark's size, at most the cell's width.
        var side: Double

        static let gap = 1.5

        var size: CGSize {
            CGSize(width: Double(columns) * width + Double(columns - 1) * Self.gap,
                   height: Double(rows) * side + Double(rows - 1) * Self.gap)
        }
    }

    /// The largest marks that hold `n` checks in `size`, spaced about as
    /// evenly across as down, or nil when they'd be too small to read.
    static func cells(_ n: Int, in size: CGSize) -> Cells? {
        guard n > 0 else { return nil }
        let gap = Cells.gap
        var best: Cells?
        for rows in 1...min(8, n) {
            let columns = (n + rows - 1) / rows
            let width = (size.width - gap * Double(columns - 1)) / Double(columns)
            let side = min(width, 7.5, (size.height - gap * Double(rows - 1)) / Double(rows))
            guard side >= 3.5, rows == 1 || width <= 1.5 * side, side > (best?.side ?? 0) + 0.01 else { continue }
            best = Cells(rows: rows, columns: columns, width: width, side: side)
        }
        return best
    }

    var total: Int { counts.up + counts.warning + counts.down + counts.unknown }

    var body: some View {
        GeometryReader { g in
            if let c = Self.cells(total, in: g.size) {
                grid(c).frame(width: c.size.width, height: c.size.height)
            } else {
                StackBar(counts: counts, palette: palette, vibrant: vibrant)
            }
        }
    }

    func grid(_ c: Cells) -> some View {
        let p = palette
        let n = counts
        let up = vibrant ? p.up.opacity(0.4) : p.calmUp
        return Canvas { ctx, _ in
            var k = 0
            func draw(_ count: Int, _ mark: Mark, _ color: Color) {
                for _ in 0..<count {
                    var m = ctx
                    m.translateBy(x: Double(k / c.rows) * (c.width + Cells.gap) + (c.width - c.side) / 2,
                                  y: Double(k % c.rows) * (c.side + Cells.gap))
                    CardMark.draw(mark, in: m, size: c.side, color: color)
                    k += 1
                }
            }
            draw(n.up, .up, up)
            draw(n.warning, .degraded, p.warn)
            draw(n.down, .down, p.down)
            draw(n.unknown, .unknown, p.unknown)
        }
    }
}

/// A widget section's heading: symbol, title, and a count at the right.
struct WidgetHeading: View {
    var symbol: String?
    var title: String
    var meta: String
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        HStack(spacing: 5) {
            if p.style.caps {
                Text(title.uppercased(with: L10n.locale)).font(t.font(9.5, .semibold)).tracking(1.3).foregroundStyle(p.accent)
            } else {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                Text(title)
            }
            Spacer(minLength: 4)
            Text(meta).fontWeight(.medium).foregroundStyle(p.l3)
        }
        .font(t.font(11, .semibold)).foregroundStyle(p.l2)
        .lineLimit(1)
        .padding(.bottom, p.style.caps ? 6 : 5)
    }
}

struct WidgetSeen: View {
    var seen: SeenFromSection
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "target", title: tr("Seen from"), meta: "", p: p, t: t)
            FlowLayout(spacing: 5) {
                if let problems = seen.problems {
                    if problems.isEmpty {
                        chip(.up, tr("All \(seen.calm) report no problem"), nil, calm: true)
                    } else {
                        ForEach(problems.prefix(2)) { o in chip(o.mark, o.name, o.note, calm: false) }
                        // Problems left out for room are counted as such, never as ok.
                        if problems.count > 2 { chip(problems[2].mark, tr("+\(problems.count - 2) more"), nil, calm: false) }
                        if seen.calm > 0 { chip(.up, tr("\(seen.calm) others ok"), nil, calm: true) }
                    }
                } else {
                    chip(.offline, tr("Not known now"), nil, calm: false)
                }
            }
        }
    }

    func chip(_ m: Mark, _ name: String, _ note: String?, calm: Bool) -> some View {
        HStack(spacing: 5) {
            CardMark(mark: m, size: calm ? 9 : 10, color: p.listColor(m))
            Text(name).foregroundStyle(calm ? p.l2 : p.l1)
            if let note { Text(note).font(t.font(11)).foregroundStyle(p.l2) }
        }
        .font(t.font(11.5))
        .lineLimit(1)
        .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 8))
        .background {
            let shape = RoundedRectangle(cornerRadius: p.style.chip(7), style: .continuous)
            if calm {
                shape.strokeBorder(p.isDark ? p.sep : Color.black.opacity(0.12), lineWidth: 0.5)
            } else {
                shape.fill(m == .unknown || m == .offline ? p.unknown.opacity(0.18) : p.color(m).opacity(0.15))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetAttention: View {
    var attention: AttentionSection
    var rows: Int
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "exclamationmark.triangle", title: tr("Needs attention"), meta: "\(attention.total)", p: p, t: t)
            ForEach(Array(attention.items.prefix(rows).enumerated()), id: \.element.id) { i, a in
                if i > 0 { Rectangle().fill(p.sep).frame(height: 0.5) }
                Link(destination: WidgetLinks.attention(a)) {
                    HStack(alignment: .top, spacing: 8) {
                        CardMark(mark: a.mark, size: 12, color: p.color(a.mark)).frame(width: 12).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            RouteLine(route: a.route, arrow: p.l3).font(t.font(12, .medium)).foregroundStyle(p.l1)
                            Text(subtitle(a)).font(t.font(10.5)).foregroundStyle(p.l2)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, i == 0 ? 1 : 4).padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(a.title), \(a.pill.text)"))
            }
        }
    }

    func subtitle(_ a: AttentionSection.Item) -> String {
        Words.join([a.observerName.isEmpty ? Words.kind(a.kind) : a.observerName,
                    a.since.map { Words.span(since: $0, now: attention.now) } ?? (a.observerName.isEmpty ? "" : Words.kind(a.kind))])
    }
}

struct WidgetApplications: View {
    var apps: ApplicationsSection
    var rows: Int
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "square.3.layers.3d", title: tr("Applications"), meta: "\(apps.rows.count)", p: p, t: t)
            let (shown, rest) = apps.cut(rows)
            ForEach(shown) { a in
                HStack(spacing: 7) {
                    CardMark(mark: a.mark, size: 9, color: p.listColor(a.mark))
                    Text(a.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 2.5) {
                        ForEach(Array(a.services.prefix(8).enumerated()), id: \.offset) { _, m in
                            CardMark(mark: m, size: 7, color: p.listColor(m))
                        }
                    }
                }
                .font(t.font(12))
                .padding(.vertical, 2)
                .opacity(apps.isCurrent ? 1 : 0.55)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(a.name), \(a.note)"))
            }
            if !rest.isEmpty { more(rest) }
        }
    }

    /// Applications left out for room: how many, and their marks, trouble
    /// first, so trouble left out still shows.
    func more(_ rest: [ApplicationsSection.Row]) -> some View {
        let marks = Mark.troubleFirst(rest, by: \.mark)
        return HStack(spacing: 7) {
            Color.clear.frame(width: 9, height: 1)
            Text(tr("+\(rest.count) more")).foregroundStyle(p.l2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2.5) {
                ForEach(Array(marks.prefix(8).enumerated()), id: \.offset) { _, r in CardMark(mark: r.mark, size: 7, color: p.listColor(r.mark)) }
                if marks.count > 8 { Text(verbatim: "+\(marks.count - 8)").font(t.font(9.5)).foregroundStyle(p.l3) }
            }
        }
        .font(t.font(12))
        .padding(.vertical, 2)
        .opacity(apps.isCurrent ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tr("+\(rest.count) more") + ": " + rest.map { "\($0.name), \($0.note)" }.joined(separator: " · ")))
    }
}

/// Said in place of a list when the verdict is all there is.
struct WidgetEmpty: View {
    var status: StatusSection
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeading(symbol: "exclamationmark.triangle", title: tr("Needs attention"), meta: "", p: p, t: t)
            Text(status.isBlind ? tr("Not known now") : tr("Nothing needs attention"))
                .font(t.font(12)).foregroundStyle(p.l2)
        }
    }
}

/// Fleet in the extra large widget's right column, as many of its
/// groups as fit; those left out are counted, their nodes' marks kept.
struct WidgetFleet: View {
    var fleet: FleetSection
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "square.grid.2x2", title: tr("Fleet"),
                          meta: fleet.meta, p: p, t: t)
                .padding(.bottom, 2)
            ViewThatFits(in: .vertical) {
                ForEach(Array(stride(from: fleet.groups.count, through: 1, by: -1)), id: \.self) { n in
                    grid(shown: n)
                }
            }
        }
    }

    /// The first `shown` groups, edges first, then a cell for the rest.
    func grid(shown: Int) -> some View {
        let edges = Array(fleet.edges.prefix(shown))
        let servers = Array(fleet.servers.prefix(shown - edges.count))
        let rest = Array(fleet.edges.dropFirst(edges.count) + fleet.servers.dropFirst(servers.count))
        return VStack(alignment: .leading, spacing: 0) {
            FleetGrid(groups: edges, isCurrent: fleet.isCurrent, p: p, t: t, marks: 5)
            if !edges.isEmpty, !servers.isEmpty || !rest.isEmpty {
                Rectangle().fill(p.sep).frame(height: 0.5).padding(.vertical, 7)
            }
            FleetGrid(groups: servers, isCurrent: fleet.isCurrent, p: p, t: t, marks: 5, more: rest)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "CPU ▬▬▬▏ 26%": a label, the meter against its limit, the value, and
/// where there's room what it measures: "8.4 / 16 GiB".
@MainActor
struct WidgetMeter {
    var label: String
    var meter: ServerCardModel.Meter
    var p: CardsPalette
    var t: CardsType
    var size = false

    /// As a row of a Grid of meters.
    var row: some View {
        GridRow {
            labelText.frame(minWidth: 30, alignment: .leading)
            Meter(percent: meter.percent, limit: meter.limit, palette: p)
            valueText
            if size {
                Text(meter.detail).font(t.font(10.5)).foregroundStyle(p.l3).fixedSize()
                    .gridColumnAlignment(.trailing)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    var labelText: some View {
        Text(label).font(t.font(10.5)).foregroundStyle(p.l2).fixedSize()
    }

    var valueText: some View {
        Text(meter.percent.map { Words.percent($0, digits: 0) } ?? "—")
            .font(t.mono(11, .semibold)).foregroundStyle(meter.percent == nil ? p.l3 : p.l1)
            .frame(width: 32, alignment: .trailing)
    }

    var spoken: Text {
        let value = meter.percent.map { "\(label) \(Words.percent($0, digits: 0))" } ?? "\(label) \(tr("unknown"))"
        return Text(size && !meter.detail.isEmpty ? value + ", " + meter.detail : value)
    }
}

/// A Server widget's own card: name, the three meters, state and age;
/// as wide as the widget, what each meter measures.
struct WidgetServerCard: View {
    var card: ServerCardModel
    var isMac: Bool
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext
    var sizes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                NodeAvatar(provider: card.isMissing ? "" : card.provider, kind: card.kind, size: 26, p: p,
                           symbol: isMac ? "apple.logo" : nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.name).font(t.font(12.5, .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    Text(card.isMissing ? card.place : Words.join([card.place, card.provider.isEmpty ? card.origin?.detail ?? "" : card.provider]))
                        .font(t.font(10.5)).foregroundStyle(p.l2).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            // One grid, so the label column fits the longest label.
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 8) {
                WidgetMeter(label: tr("CPU"), meter: card.cpu, p: p, t: t, size: sizes).row
                WidgetMeter(label: tr("Mem"), meter: card.memory, p: p, t: t, size: sizes).row
                WidgetMeter(label: tr("Disk"), meter: card.disk, p: p, t: t, size: sizes).row
            }
            .padding(.top, 13).padding(.bottom, 10)
            Spacer(minLength: 0)
            HStack {
                PillView(pill: card.pill, palette: p, type: t)
                Spacer(minLength: 4)
                // A CACHED pill already says the age is of history.
                if let at = card.sampledAt {
                    // A direct snapshot keeps the time it was read: a new
                    // hand-off can't renew it.
                    if card.origin != nil {
                        Text(Words.asOf(at)).font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        Age(date: at, now: card.now, live: ctx.liveDates, compact: true)
                            .font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
        }
    }
}

/// A medium Server widget's right side: its services, and what it
/// observes from there.
struct WidgetServices: View {
    var card: ServerCardModel
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: nil, title: tr("Services"), meta: "\(card.services.count)", p: p, t: t)
            ForEach(card.services.prefix(5)) { s in
                HStack(spacing: 7) {
                    CardMark(mark: s.mark, size: 9, color: p.listColor(s.mark))
                    Text(s.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    // A note is a word or two that says why: whole, while the
                    // name gives way.
                    if !s.note.isEmpty { Text(s.note).font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).fixedSize() }
                }
                .font(t.font(12))
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
            if card.services.isEmpty {
                Text(card.isWithheld ? tr("Not known now") : tr("No services on this node"))
                    .font(t.font(12)).foregroundStyle(p.l3)
            }
            Spacer(minLength: 0)
            if let o = card.observes.first {
                VStack(spacing: 0) {
                    Rectangle().fill(p.sep).frame(height: 0.5)
                    // Its verdict comes last, so where the line is short the
                    // rest gives way first: the symbol, then the words.
                    ViewThatFits(in: .horizontal) {
                        observes(o, symbol: true, label: true)
                        observes(o, symbol: false, label: true)
                        observes(o, symbol: true, label: false)
                    }
                    .font(t.font(10.5)).foregroundStyle(p.l2)
                    .padding(.top, 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Words.join([tr("From here"), o.text])))
            }
        }
    }
}

extension WidgetServices {
    /// What the observer on this node sees: "◎ From here ● 9 checks · all
    /// pass", with or without its symbol and its words.
    func observes(_ o: ServerCardModel.Observes, symbol: Bool, label: Bool) -> some View {
        HStack(spacing: 4) {
            if symbol { Image(systemName: "target").font(.system(size: 9.5)) }
            if label { Text(tr("From here")).lineLimit(1).fixedSize() }
            Spacer(minLength: 2)
            CardMark(mark: o.mark, size: 9, color: p.color(o.mark))
            Text(o.text).fontWeight(.medium).foregroundStyle(p.l1).lineLimit(1).fixedSize()
        }
    }
}

/// The background a cards widget sits on: the theme's ground, as the
/// panel's; on glass, a tint over what WidgetKit draws.
struct CardsWidgetBackground: View {
    var ctx: RenderContext

    var body: some View {
        let dark = ctx.effectiveScheme == .dark
        let p = CardsPalette.resolve(ctx)
        if p.style.surface != .glass {
            ZStack { CardsGround(p: p, live: false, shape: Rectangle()) }
        } else if ctx.reduceTransparency {
            Rectangle().fill(dark ? Color(.sRGB, red: 0.13, green: 0.13, blue: 0.15) : Color(.sRGB, red: 0.96, green: 0.96, blue: 0.97))
        } else if let token = ctx.theme.color("panelMaterial", dark: dark) {
            Rectangle().fill(Color(token))
        } else {
            Rectangle().fill(dark ? Color(.sRGB, red: 28 / 255, green: 28 / 255, blue: 34 / 255, opacity: 0.5)
                                  : Color(.sRGB, red: 250 / 255, green: 250 / 255, blue: 253 / 255, opacity: 0.58))
        }
    }
}

/// The links widgets open: the panel, or the TUI on an attention entry.
public enum WidgetLinks {
    public static let scheme = "topophany-bar"
    public static let panel = URL(string: "\(scheme)://panel")!

    public static func attention(_ a: AttentionSection.Item) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "attention"
        c.queryItems = [URLQueryItem(name: "kind", value: a.kind), URLQueryItem(name: "id", value: a.id)]
        return c.url ?? panel
    }
}
