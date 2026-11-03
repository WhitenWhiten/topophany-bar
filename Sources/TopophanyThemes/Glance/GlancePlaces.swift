import SwiftUI
import TopophanyKit
import TopophanySections

/// Map, Fleet and Time zones as one card, a lens each: one shows at a
/// time, the others a click away, each with its worst mark beside its name
/// while something in it is down or warns. The keyboard's focus on the map
/// shows the map.
struct GlancePlaces: View, Equatable {
    var sections: [PanelModel.Section]
    var p: CardsPalette
    var t: CardsType
    var mapFocused: Bool
    /// The lens a click chose; until then, the first.
    @State private var chosen: SectionID?
    @Environment(\.mapViewport) private var viewport

    /// `lens`: the lens chosen to begin with, as a click would leave it.
    init(sections: [PanelModel.Section], p: CardsPalette, t: CardsType, mapFocused: Bool, lens: SectionID? = nil) {
        self.sections = sections
        self.p = p
        self.t = t
        self.mapFocused = mapFocused
        _chosen = State(initialValue: lens)
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sections == rhs.sections && lhs.p == rhs.p && lhs.t == rhs.t && lhs.mapFocused == rhs.mapFocused
    }

    var lens: SectionID {
        let ids = sections.map(\.id)
        if mapFocused, ids.contains(.map) { return .map }
        if let chosen, ids.contains(chosen) { return chosen }
        return ids.first ?? .map
    }

    var body: some View {
        let lens = self.lens
        Card(p: p) {
            HStack(spacing: 2) {
                if sections.count > 1 {
                    ForEach(sections) { s in
                        LensButton(title: Self.title(s.id), trouble: s.id == lens ? nil : Self.trouble(s), selected: s.id == lens,
                                   p: p, t: t) { chosen = s.id }
                    }
                } else {
                    Text(Self.title(lens)).font(t.font(11.5, .semibold)).foregroundStyle(p.l2)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                meta(lens)
            }
            .padding(.bottom, sections.count > 1 ? 6 : 7)
            ForEach(sections.filter { $0.id == lens }) { s in content(s) }
        }
    }

    @ViewBuilder func meta(_ lens: SectionID) -> some View {
        Group {
            if lens == .map, viewport?.isSelected == true {
                // Selected, what the keys do, clear of the map.
                Text(tr("↑ ↓ zoom · esc")).foregroundStyle(p.accent).lineLimit(1)
                    .accessibilityHidden(true)
            } else if let s = sections.first(where: { $0.id == lens }) {
                FittedText(parts: Self.meta(s)).foregroundStyle(p.l3)
            }
        }
        .font(t.font(10.5, .medium))
        .animation(Highlight.easing(viewport?.isSelected == true), value: viewport?.isSelected == true)
    }

    @ViewBuilder func content(_ s: PanelModel.Section) -> some View {
        switch s {
        case .map(let m):
            VStack(alignment: .leading, spacing: 0) {
                MapCanvas(map: m, p: p, t: t, focused: mapFocused)
                    .frame(height: CardsMapCard.height * t.scale)
                    .padding(.horizontal, -11)
                if MapFoot.says(m) { MapFoot(map: m, p: p, t: t).padding(.top, 7) }
            }
            .id("map")
            // Another lens in its place: the wheel no longer finds the map
            // where it was.
            .onDisappear { viewport?.frame = .zero }
        case .fleet(let f):
            FleetBody(fleet: f, p: p, t: t)
        case .zones(let z):
            ZonesList(zones: z, p: p, t: t)
        default:
            EmptyView()
        }
    }

    static func title(_ id: SectionID) -> String {
        switch id {
        case .map: tr("Map")
        case .fleet: tr("Fleet")
        case .zones: tr("Time zones")
        default: ""
        }
    }

    /// What its card's title says beside it.
    static func meta(_ s: PanelModel.Section) -> String {
        switch s {
        case .map(let m): tr("\(m.places.count) places")
        case .fleet(let f): f.meta
        case .zones(let z): Words.join([tr("\(z.zones.count) zones"), tr("\(z.serverCount) servers")])
        default: ""
        }
    }

    /// Down, else warn, where any node in a lens is: what a lens not shown
    /// says beside its name.
    static func trouble(_ s: PanelModel.Section) -> Mark? {
        let marks: [Mark] = switch s {
        case .map(let m): m.nodes.map(\.mark)
        case .fleet(let f): (f.edges + f.servers).flatMap { $0.nodes.map(\.mark) }
        case .zones(let z): z.zones.flatMap { $0.servers.map(\.mark) }
        default: []
        }
        return marks.contains(.down) ? .down : marks.contains(.degraded) ? .degraded : nil
    }
}

/// A lens's name: filled while it's shown, faintly under the pointer
/// otherwise.
struct LensButton: View {
    var title: String
    var trouble: Mark?
    var selected: Bool
    var p: CardsPalette
    var t: CardsType
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let trouble { CardMark(mark: trouble, size: 8.5, color: p.color(trouble)) }
            }
            .font(t.font(11.5, selected ? .semibold : .medium))
            .foregroundStyle(selected ? p.l1 : hover ? p.l1 : p.l2)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 3.5)
            .background(Capsule().fill(p.fill2).opacity(selected ? 1 : hover ? 0.6 : 0))
            .contentShape(Capsule())
            .animation(Highlight.easing(hover), value: hover)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .accessibilityLabel(Text(Words.join([title, trouble?.word ?? ""])))
        .accessibilityAddTraits(selected ? [.isSelected, .isHeader] : [])
    }
}
