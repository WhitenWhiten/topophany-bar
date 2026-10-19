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
    var t: CardsType { CardsType(scale: 1) }

    var body: some View {
        let p = self.p
        Group {
            switch model.kind {
            case .status: status(p)
            case .server: server(p)
            }
        }
        .padding(14)
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .foregroundStyle(p.l1)
        .environment(\.colorScheme, ctx.effectiveScheme)
    }

    // MARK: Status

    @ViewBuilder func status(_ p: CardsPalette) -> some View {
        let w = WidgetStatus(status: model.status, p: p, t: t, ctx: ctx)
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 0) {
                w.compact
                Spacer(minLength: 0)
                w.foot(wide: false)
            }
        case .medium:
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    w.compact
                    Spacer(minLength: 0)
                    w.foot(wide: false)
                }
                .frame(width: 136)
                right(p, attentionRows: 3, appRows: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case .large:
            large(p, w, appRows: 6)
        case .extraLarge:
            HStack(alignment: .top, spacing: 24) {
                large(p, w, appRows: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 0) {
                    if hasAttention, let apps = model.panel.applications {
                        WidgetApplications(apps: apps, rows: 6, p: p, t: t)
                        WidgetServers(cards: model.panel.servers, p: p, t: t, ctx: ctx).padding(.top, 12)
                    } else {
                        WidgetServers(cards: model.panel.servers, p: p, t: t, ctx: ctx)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    var hasAttention: Bool { !(model.panel.attention?.items.isEmpty ?? true) }

    func large(_ p: CardsPalette, _ w: WidgetStatus, appRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            w.big
            if let seen = model.panel.seen {
                WidgetSeen(seen: seen, p: p, t: t).padding(.top, 12)
            }
            right(p, attentionRows: 3, appRows: appRows).padding(.top, 12)
            Spacer(minLength: 0)
            w.foot(wide: true)
        }
    }

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
        } else {
            HStack(alignment: .top, spacing: 16) {
                left.frame(width: 136)
                WidgetServices(card: card, p: p, t: t)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    var isMac: Bool { if case .server(_, true) = model.kind { true } else { false } }

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
                BrandMark().frame(width: 18, height: 18)
            }
            Text(status.shortTitle).font(t.font(16, .semibold)).tracking(-0.24).lineLimit(1)
                .padding(.top, 10)
            Text(status.shortSubtitle).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1)
                .padding(.top, 2).padding(.bottom, 9)
            bar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.join([status.title, status.shortSubtitle])))
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
                BrandMark().frame(width: 18, height: 18)
            }
            .accessibilityElement(children: .combine)
            bar.padding(.top, 12).padding(.bottom, 7)
            if !status.isBlind, let c = status.counts?.complete { legend(c) }
        }
    }

    @ViewBuilder var bar: some View {
        if !status.isBlind, let c = status.counts?.complete {
            StackBar(counts: c, palette: p)
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
            CardMark(mark: m, size: 9, color: p.color(m)).opacity(n == 0 ? 0.45 : 1)
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

/// A widget section's heading: symbol, title, and a count at the right.
struct WidgetHeading: View {
    var symbol: String?
    var title: String
    var meta: String
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
            Text(title)
            Spacer(minLength: 4)
            Text(meta).fontWeight(.medium).foregroundStyle(p.l3)
        }
        .font(t.font(11, .semibold)).foregroundStyle(p.l2)
        .lineLimit(1)
        .padding(.bottom, 5)
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
            CardMark(mark: m, size: calm ? 9 : 10, color: p.color(m))
            Text(name).foregroundStyle(calm ? p.l2 : p.l1)
            if let note { Text(note).font(t.font(11)).foregroundStyle(p.l2) }
        }
        .font(t.font(11.5))
        .lineLimit(1)
        .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 8))
        .background {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                            Text(routeText(a.route, arrow: p.l3)).font(t.font(12, .medium)).foregroundStyle(p.l1)
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
            ForEach(apps.rows.prefix(rows)) { a in
                HStack(spacing: 7) {
                    CardMark(mark: a.mark, size: 9, color: p.color(a.mark))
                    Text(a.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 2.5) {
                        ForEach(Array(a.services.prefix(8).enumerated()), id: \.offset) { _, m in
                            CardMark(mark: m, size: 7, color: p.color(m))
                        }
                    }
                }
                .font(t.font(12))
                .padding(.vertical, 2)
                .opacity(apps.isCurrent ? 1 : 0.55)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(a.name), \(a.note)"))
            }
        }
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

/// Pinned servers, one line of meters each, in the extra large widget.
struct WidgetServers: View {
    var cards: [ServerCardModel]
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "server.rack", title: tr("Servers"), meta: tr("\(cards.count) pinned"), p: p, t: t)
            if cards.isEmpty {
                Text(tr("Pin servers in Settings")).font(t.font(12)).foregroundStyle(p.l3).padding(.top, 2)
            }
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(c.name).font(t.font(12, .semibold)).lineLimit(1)
                        Spacer(minLength: 6)
                        PillView(pill: c.pill, palette: p, type: t)
                    }
                    HStack(spacing: 12) {
                        WidgetMeter(label: tr("CPU"), meter: c.cpu, p: p, t: t)
                        WidgetMeter(label: tr("Mem"), meter: c.memory, p: p, t: t)
                        WidgetMeter(label: tr("Disk"), meter: c.disk, p: p, t: t)
                    }
                }
                .padding(.top, 7).padding(.bottom, 2)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(p.sep).frame(height: 0.5) } }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// "CPU ▬▬▬▏ 26%": a label, the meter against its limit, the value.
struct WidgetMeter: View {
    var label: String
    var meter: ServerCardModel.Meter
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        HStack(spacing: 6) {
            labelText.frame(minWidth: 30, alignment: .leading)
            Meter(percent: meter.percent, limit: meter.limit, palette: p)
            valueText
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// As a row of a Grid of meters.
    var row: some View {
        GridRow {
            labelText.frame(minWidth: 30, alignment: .leading)
            Meter(percent: meter.percent, limit: meter.limit, palette: p)
            valueText
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
        Text(meter.percent.map { "\(label) \(Words.percent($0, digits: 0))" } ?? "\(label) \(tr("unknown"))")
    }
}

/// A Server widget's own card: name, the three meters, state and age.
struct WidgetServerCard: View {
    var card: ServerCardModel
    var isMac: Bool
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                NodeAvatar(provider: card.isMissing ? "" : card.provider, kind: card.kind, size: 26, p: p,
                           symbol: isMac ? "laptopcomputer" : nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.name).font(t.font(12.5, .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    Text(card.isMissing ? card.place : Words.join([card.place, card.provider]))
                        .font(t.font(10.5)).foregroundStyle(p.l2).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            // One grid, so the label column fits the longest label.
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 8) {
                WidgetMeter(label: tr("CPU"), meter: card.cpu, p: p, t: t).row
                WidgetMeter(label: tr("Mem"), meter: card.memory, p: p, t: t).row
                WidgetMeter(label: tr("Disk"), meter: card.disk, p: p, t: t).row
            }
            .padding(.top, 13).padding(.bottom, 10)
            Spacer(minLength: 0)
            HStack {
                PillView(pill: card.pill, palette: p, type: t)
                Spacer(minLength: 4)
                // A CACHED pill already says the age is of history.
                if let at = card.sampledAt {
                    Age(date: at, now: card.now, live: ctx.liveDates, compact: true)
                        .font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).minimumScaleFactor(0.8)
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
                    CardMark(mark: s.mark, size: 9, color: p.color(s.mark))
                    Text(s.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    if !s.note.isEmpty { Text(s.note).font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1) }
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
                    HStack(spacing: 4) {
                        Image(systemName: "target").font(.system(size: 9.5))
                        Text(tr("From here")).lineLimit(1).fixedSize()
                        Spacer(minLength: 2)
                        CardMark(mark: o.mark, size: 9, color: p.color(o.mark))
                        Text(o.text).fontWeight(.medium).foregroundStyle(p.l1).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .font(t.font(10.5)).foregroundStyle(p.l2)
                    .padding(.top, 6)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The background a Native widget sits on.
struct CardsWidgetBackground: View {
    var ctx: RenderContext

    var body: some View {
        let dark = ctx.effectiveScheme == .dark
        if ctx.reduceTransparency {
            Rectangle().fill(dark ? Color(.sRGB, red: 0.13, green: 0.13, blue: 0.15) : Color(.sRGB, red: 0.96, green: 0.96, blue: 0.97))
        } else if let token = ctx.theme.color("panelMaterial") {
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
