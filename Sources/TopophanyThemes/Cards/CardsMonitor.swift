import SwiftUI
import TopophanySections

/// The same head, type, dividers and footer as CardsService. Only the content
/// changes: one conclusion and one reading, with evidence disclosed on demand.
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
                            Image(systemName: monitor.expanded ? "chevron.down" : "chevron.right").font(t.font(9)).foregroundStyle(p.l3)
                        }
                        Text(monitor.subtitle).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1).truncationMode(.middle)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(card.name + ", " + card.pill.text))
            .accessibilityValue(Text(monitor.expanded ? tr("Expanded") : tr("Collapsed")))
            Text(monitor.summary).font(t.font(12)).foregroundStyle(p.l1).lineLimit(2).padding(.top, 10)
            if !monitor.reading.isEmpty {
                Text(monitor.reading).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1).truncationMode(.middle).padding(.top, 3)
            }
            if monitor.expanded {
                ForEach(monitor.checks.prefix(8)) { check in
                    Rectangle().fill(p.sep).frame(height: 0.5).padding(.vertical, 8)
                    if monitor.pin.kind == .link {
                    HStack(spacing: 6) {
                        CardMark(mark: check.mark, size: 9, color: p.listColor(check.mark))
                        Text(check.name).font(t.font(11.5, .medium)).foregroundStyle(p.l1).lineLimit(1)
                    }
                    Text(check.source).font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).padding(.top, 2)
                    }
                    if check.summary != monitor.summary { Text(check.summary).font(t.font(11)).foregroundStyle(p.l2).lineLimit(2).padding(.top, 4) }
                    if !check.reading.isEmpty && check.reading != monitor.reading { Text(check.reading).font(t.font(11)).foregroundStyle(p.l2).lineLimit(2).truncationMode(.middle).padding(.top, 2) }
                    ForEach(check.fields) { field in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(field.label).foregroundStyle(p.l3)
                            Spacer(minLength: 0)
                            Text(field.value).foregroundStyle(p.l2).multilineTextAlignment(.trailing).lineLimit(3).help(field.value)
                        }.font(t.font(11)).padding(.top, 3)
                    }
                    if !check.code.isEmpty { Text(check.code).font(t.mono(10)).foregroundStyle(p.l3).lineLimit(2).padding(.top, 2) }
                    if case .samples = check.history {
                        HStack(spacing: 8) {
                            ServiceSpark(history: check.history, count: 34, p: p).frame(height: 18)
                            if let ms = check.p50 { Text(check.p50Label + " " + Words.ms(ms)).font(t.font(10.5)).foregroundStyle(p.l3).fixedSize() }
                        }.padding(.top, 6)
                    }
                }
                if monitor.checks.count > 8 {
                    Button(tr("\(monitor.checks.count - 8) more in Topophany")) { actions.openTerminal() }
                        .buttonStyle(.plain).font(t.font(11)).foregroundStyle(p.l2).padding(.top, 8)
                }
            }
            HStack {
                Text(card.age).lineLimit(1)
                Spacer(minLength: 0)
            }.font(t.font(10.5)).foregroundStyle(p.l3).padding(.top, 8)
        }
        .modifier(FocusRing(on: focused, p: p))
        .id(card.focusID)
    }
}
