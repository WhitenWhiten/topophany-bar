import SwiftUI
import TopophanySections

/// A pinned list as tiles, two to a row: an item's mark and name, and its
/// reading beneath. A click opens an item in place, its whole card across
/// the row as Native draws it, and a click on the card closes it again. A
/// pinned check opens as its card's own disclosure does, so ↵ opens it
/// too.
struct GlancePinned: View {
    enum Item: Hashable, Identifiable {
        case service(ServiceCardModel)
        case server(ServerCardModel)

        var id: String {
            switch self {
            case .service(let c): c.focusID
            case .server(let c): "server:" + c.id
            }
        }

        var mark: Mark {
            switch self {
            case .service(let c): c.mark
            case .server(let c): c.mark
            }
        }

        var name: String {
            switch self {
            case .service(let c): c.name
            case .server(let c): c.name
            }
        }
    }

    var title: String
    var meta: String
    var items: [Item]
    var p: CardsPalette
    var t: CardsType
    var focus: String?
    /// Items a click opened, by ID; a pinned check keeps its own.
    @State private var opened: Set<String>
    @Environment(\.panelActions) private var actions

    /// `opened`: the items open to begin with, by ID, as clicks would leave
    /// them.
    init(title: String, meta: String, items: [Item], p: CardsPalette, t: CardsType, focus: String?, opened: Set<String> = []) {
        self.title = title
        self.meta = meta
        self.items = items
        self.p = p
        self.t = t
        self.focus = focus
        _opened = State(initialValue: opened)
    }

    func isOpen(_ i: Item) -> Bool {
        if case .service(let c) = i, let m = c.monitor { return m.expanded }
        return opened.contains(i.id)
    }

    func toggle(_ i: Item) {
        if case .service(let c) = i, let m = c.monitor {
            actions.toggleMonitor(m.pin)
        } else if opened.contains(i.id) {
            opened.remove(i.id)
        } else {
            opened.insert(i.id)
        }
    }

    /// Two to a row, in order; an open item has a row of its own.
    var rows: [[Item]] {
        var out: [[Item]] = []
        var single: Item?
        for i in items {
            if isOpen(i) {
                if let s = single { out.append([s]) }
                single = nil
                out.append([i])
            } else if let s = single {
                out.append([s, i])
                single = nil
            } else {
                single = i
            }
        }
        if let s = single { out.append([s]) }
        return out
    }

    var body: some View {
        Card(p: p) {
            CardTitle(symbol: "pin", title: title, meta: meta, p: p, t: t)
            VStack(spacing: 6) {
                ForEach(rows, id: \.first?.id) { row in
                    if row.count == 1, isOpen(row[0]) {
                        open(row[0])
                    } else {
                        HStack(spacing: 6) {
                            tile(row[0])
                            if row.count > 1 { tile(row[1]) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                        }
                        // Tiles side by side are as tall as each other.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    func tile(_ i: Item) -> some View {
        GlanceTile(mark: i.mark, name: i.name, focused: focus == i.id, spoken: spoken(i), p: p, t: t) { toggle(i) } detail: {
            detail(i)
        }
        .id(i.id)
    }

    /// The item's card, whole, as Native draws it.
    func open(_ i: Item) -> some View {
        Group {
            switch i {
            case .service(let c):
                if let m = c.monitor {
                    CardsMonitor(card: c, monitor: m, p: p, t: t, focused: focus == c.focusID)
                } else {
                    CardsService(card: c, p: p, t: t, focused: focus == c.focusID)
                }
            case .server(let c):
                CardsServer(card: c, p: p, t: t, focused: focus == "server:" + c.id)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 10, bottom: 10, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.fill2.opacity(0.55)))
        .contentShape(Rectangle())
        // Its own buttons take their clicks first.
        .onTapGesture { toggle(i) }
        .accessibilityAction(.escape) { toggle(i) }
    }

    /// Beneath the name: a check's conclusion and its recent samples; a
    /// service's samples from its first observer and their median; a
    /// server's three meters.
    @ViewBuilder func detail(_ i: Item) -> some View {
        switch i {
        case .service(let c):
            if let m = c.monitor {
                Text(m.summary).font(t.font(11)).foregroundStyle(p.l2).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let check = m.checks.first, case .samples = check.history {
                    ServiceSpark(history: check.history, count: 22, p: p).frame(height: 14)
                }
            } else if let o = c.observers.first {
                HStack(spacing: 6) {
                    ServiceSpark(history: o.history, count: 22, p: p).frame(height: 16).frame(maxWidth: .infinity)
                    Text(o.p50.map(Words.ms) ?? "—").font(t.mono(10.5, .medium)).foregroundStyle(p.l2).fixedSize()
                }
            } else {
                Text(c.quiet.title).font(t.font(11)).foregroundStyle(p.l3).lineLimit(1)
            }
        case .server(let c):
            if c.isMissing || c.isWithheld || c.hasNoCurrentSample {
                Text(c.isMissing ? c.place : c.age).font(t.font(11)).foregroundStyle(p.l3).lineLimit(1)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    meter(tr("CPU"), c.cpu)
                    meter(tr("Memory"), c.memory)
                    meter(tr("Disk"), c.disk)
                }
            }
        }
    }

    /// A reading over its meter, and what it measures beneath.
    func meter(_ label: String, _ m: ServerCardModel.Meter) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                if m.isOverLimit { CardMark(mark: .degraded, size: 8, color: p.warn) }
                Text(m.percent.map { Words.percent($0, digits: 0) } ?? "—").font(t.mono(11, .semibold)).foregroundStyle(p.l1)
            }
            Meter(percent: m.percent, limit: m.limit, palette: p, height: 3)
            Text(label).font(t.font(9.5)).foregroundStyle(p.l3).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func spoken(_ i: Item) -> String {
        switch i {
        case .service(let c):
            if let m = c.monitor { return Words.join([c.pill.text, m.summary]) }
            return Words.join([c.pill.text, c.observers.first.flatMap { $0.p50.map(Words.ms) } ?? c.quiet.title])
        case .server(let c):
            let meters = [(tr("CPU"), c.cpu), (tr("Memory"), c.memory), (tr("Disk"), c.disk)].compactMap { label, m in
                m.percent.map { "\(label) \(Words.percent($0, digits: 0))" }
            }
            return Words.join([c.pill.text] + (c.isWithheld || c.hasNoCurrentSample ? [c.age] : meters))
        }
    }
}

/// A pinned item's tile: its mark and name over its detail, tinted in its
/// mark's color while it's down or warns, lighter under the pointer, and
/// ringed in the accent while the keyboard is on it.
struct GlanceTile<Detail: View>: View {
    var mark: Mark
    var name: String
    var focused: Bool
    var spoken: String
    var p: CardsPalette
    var t: CardsType
    var action: () -> Void
    @ViewBuilder var detail: Detail
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let trouble = GlanceLayout.isTrouble(mark)
        // The mark's middle on the name's first line.
        let lift = 3.5 * t.scale
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CardMark(mark: mark, size: 10, color: p.listColor(mark))
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + lift }
                    // Two lines before it's cut: a tile is half a row.
                    Text(name).font(t.font(12, .semibold)).foregroundStyle(p.l1).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                detail
            }
            .padding(EdgeInsets(top: 8, leading: 9, bottom: 9, trailing: 9))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                shape.fill(trouble ? p.tint(mark, p.isDark ? 0.16 : 0.12) : p.fill2)
                shape.fill(p.fill2).opacity(hover ? 1 : 0)
                if trouble { shape.strokeBorder(p.color(mark).opacity(0.32), lineWidth: 0.75) }
                shape.strokeBorder(p.accent, lineWidth: 1.5).opacity(focused ? 1 : 0)
            }
            .animation(Highlight.easing(hover), value: hover)
            .animation(Highlight.easing(focused), value: focused)
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.join([name, spoken])))
        .accessibilityValue(Text(tr("Collapsed")))
        .accessibilityAddTraits(.isButton)
    }
}
