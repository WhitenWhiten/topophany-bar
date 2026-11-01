import SwiftUI
import TopophanySections

/// The same head, type and dividers as CardsService, with its age beside
/// the subtitle: one conclusion and one reading, and the evidence, packed
/// side by side, disclosed on demand.
struct CardsMonitor: View {
    var card: ServiceCardModel
    var monitor: MonitorCardModel
    var p: CardsPalette
    var t: CardsType
    var focused: Bool
    @Environment(\.panelActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { actions.toggleMonitor(monitor.pin) } label: {
                HStack(spacing: 9) {
                    NodeAvatar(provider: card.host.provider, kind: card.host.kind, size: 28, p: p)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(card.name).font(t.font(12.5, .semibold)).foregroundStyle(p.l1).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            PillView(pill: card.pill, palette: p, type: t)
                            // One chevron, turned when open, as a disclosure
                            // triangle turns: chevron.down is wider and
                            // would nudge the pill.
                            Image(systemName: "chevron.right").font(t.font(9)).foregroundStyle(p.l3)
                                .rotationEffect(.degrees(monitor.expanded ? 90 : 0))
                        }
                        HStack(spacing: 8) {
                            Text(monitor.subtitle).foregroundStyle(p.l2).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text(card.age).foregroundStyle(p.l3).lineLimit(1).fixedSize()
                        }.font(t.font(11))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(card.name + ", " + card.pill.text))
            .accessibilityValue(Text(monitor.expanded ? tr("Expanded") : tr("Collapsed")))
            Text(monitor.summary).font(t.font(12)).foregroundStyle(p.l1).lineLimit(2).padding(.top, 7)
            if !monitor.reading.isEmpty {
                Text(monitor.reading).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1).truncationMode(.middle).padding(.top, 3)
            }
            if monitor.expanded {
                ForEach(monitor.checks.prefix(8)) { check in
                    Rectangle().fill(p.sep).frame(height: 0.5).padding(.vertical, 7)
                    // A link's only check is the card itself: its name and source add nothing.
                    if monitor.pin.kind == .link, monitor.checks.count > 1 {
                    HStack(spacing: 6) {
                        CardMark(mark: check.mark, size: 9, color: p.listColor(check.mark))
                        Text(check.name).font(t.font(11.5, .medium)).foregroundStyle(p.l1).lineLimit(1)
                    }
                    Text(check.source).font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).padding(.top, 2)
                    }
                    if check.summary != monitor.summary { Text(check.summary).font(t.font(11)).foregroundStyle(p.l2).lineLimit(2).padding(.top, 4) }
                    if !check.reading.isEmpty && check.reading != monitor.reading { Text(check.reading).font(t.font(11)).foregroundStyle(p.l2).lineLimit(2).truncationMode(.middle).padding(.top, 2) }
                    if !check.fields.isEmpty {
                        // Side by side while they fit; a long one takes its own row.
                        FlowLayout(spacing: 12, lineSpacing: 3) {
                            ForEach(check.fields) { field in
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(field.label).foregroundStyle(p.l3).lineLimit(1).fixedSize()
                                    Text(field.value).foregroundStyle(p.l1).lineLimit(2).truncationMode(.middle).help(field.value)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .font(t.font(11)).padding(.top, 4)
                    }
                    if !check.code.isEmpty { Text(check.code).font(t.mono(10)).foregroundStyle(p.l3).lineLimit(2).padding(.top, 2) }
                    if case .samples = check.history {
                        HStack(spacing: 8) {
                            ServiceSpark(history: check.history, count: 34, p: p).frame(height: 18)
                            if let ms = check.p50 { Text(check.p50Label + " " + Words.ms(ms)).font(t.font(10.5)).foregroundStyle(p.l3).fixedSize() }
                        }.padding(.top, 5)
                    }
                }
                if monitor.checks.count > 8 {
                    Button(tr("\(monitor.checks.count - 8) more in Topophany")) { actions.openTerminal() }
                        .buttonStyle(.plain).font(t.font(11)).foregroundStyle(p.l2).padding(.top, 8)
                }
            }
        }
        .modifier(FocusRing(on: focused, p: p))
        .id(card.focusID)
    }
}

// MARK: widgets

/// A Check widget's card: the pinned card's conclusion and reading, its
/// first check's recent samples, its state and age.
struct WidgetMonitorCard: View {
    var card: ServiceCardModel
    var m: MonitorCardModel
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext
    /// A small widget's: a medium one draws the history on its right.
    var history = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                NodeAvatar(provider: card.host.provider, kind: card.host.kind, size: 26, p: p)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.name).font(t.font(12.5, .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(m.subtitle).font(t.font(10.5)).foregroundStyle(p.l2).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Text(m.summary).font(t.font(12)).foregroundStyle(p.l1).lineLimit(2).padding(.top, 8)
            if !m.reading.isEmpty {
                Text(m.reading).font(t.font(11)).foregroundStyle(p.l2).lineLimit(history ? 1 : 2).truncationMode(.middle).padding(.top, 2)
            }
            Spacer(minLength: 0)
            if history, let check = m.checks.first, case .samples = check.history {
                ServiceSpark(history: check.history, count: 16, p: p, vibrant: ctx.widgetRendering != .fullColor)
                    .frame(height: 14).padding(.bottom, 6)
                    .accessibilityHidden(true)
            }
            HStack {
                PillView(pill: card.pill, palette: p, type: t)
                Spacer(minLength: 4)
                if let at = card.sampledAt {
                    Age(date: at, now: card.now, live: ctx.liveDates, compact: true)
                        .font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
    }
}

/// A medium Check widget's right side: the check's readings, or a link's
/// checks, then the first check's history with its median.
struct WidgetMonitorReadings: View {
    var m: MonitorCardModel
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext

    var body: some View {
        let first = m.checks.first
        VStack(alignment: .leading, spacing: 0) {
            if m.pin.kind == .link {
                WidgetHeading(symbol: nil, title: tr("Checks"), meta: "\(m.checks.count)", p: p, t: t)
                ForEach(m.checks.prefix(4)) { check in
                    HStack(spacing: 7) {
                        CardMark(mark: check.mark, size: 9, color: p.listColor(check.mark))
                        Text(check.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(t.font(12)).padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } else {
                WidgetHeading(symbol: nil, title: tr("Readings"), meta: "", p: p, t: t)
                let fields = first?.fields ?? []
                if fields.isEmpty, let code = first?.code, !code.isEmpty {
                    Text(code).font(t.mono(10.5)).foregroundStyle(p.l3).lineLimit(2)
                }
                ForEach(fields.prefix(4)) { field in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(field.label).foregroundStyle(p.l3).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(field.value).foregroundStyle(p.l1).lineLimit(1).truncationMode(.middle)
                    }
                    .font(t.font(11.5)).padding(.vertical, 1.5)
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
            if let first, case .samples = first.history {
                HStack(spacing: 6) {
                    ServiceSpark(history: first.history, count: 24, p: p, vibrant: ctx.widgetRendering != .fullColor).frame(height: 16)
                    if let ms = first.p50 { Text(first.p50Label + " " + Words.latency(ms)).font(t.font(10.5)).foregroundStyle(p.l3).fixedSize() }
                }
                .accessibilityHidden(true)
            }
        }
    }
}
