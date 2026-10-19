import SwiftUI
import TopophanySections

/// Fleet in Native: who runs what, two to a row. Edges and platforms lead,
/// with what they are; a hairline, then servers by provider. Each node's
/// mark is its own; no group is tinted for them.
struct CardsFleet: View {
    var fleet: FleetSection
    var p: CardsPalette
    var t: CardsType
    /// How many marks a group shows before counting the rest.
    var marks = 6

    var body: some View {
        Card(p: p) {
            CardTitle(symbol: "square.grid.2x2", title: tr("Fleet"),
                      meta: Words.join([tr("\(fleet.nodeCount) servers"), tr("\(fleet.providerCount) providers")]), p: p, t: t)
            FleetGrid(groups: fleet.edges, isCurrent: fleet.isCurrent, p: p, t: t, marks: marks, spacing: 5.5)
            if !fleet.edges.isEmpty, !fleet.servers.isEmpty {
                Rectangle().fill(p.sep).frame(height: 0.5).padding(.vertical, 6)
            }
            FleetGrid(groups: fleet.servers, isCurrent: fleet.isCurrent, p: p, t: t, marks: marks, spacing: 5.5)
        }
    }
}

/// Groups two to a row, every column as wide as the other; groups left
/// out for room, when there are any, take the next cell.
struct FleetGrid: View {
    var groups: [FleetSection.Group]
    var isCurrent: Bool
    var p: CardsPalette
    var t: CardsType
    var marks: Int
    var columns = 2
    var spacing = 7.0
    var more: [FleetSection.Group] = []

    var body: some View {
        let count = groups.count + (more.isEmpty ? 0 : 1)
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: spacing) {
            ForEach(Array(stride(from: 0, to: count, by: columns)), id: \.self) { i in
                GridRow {
                    ForEach(0..<columns, id: \.self) { k in
                        if i + k < groups.count {
                            FleetCell(group: groups[i + k], isCurrent: isCurrent, p: p, t: t, marks: marks)
                        } else if i + k == groups.count, !more.isEmpty {
                            FleetMore(groups: more, isCurrent: isCurrent, p: p, t: t, marks: marks)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }
}

/// Groups left out for room: how many, and their nodes' marks, trouble
/// first, so trouble left out still shows.
struct FleetMore: View {
    var groups: [FleetSection.Group]
    var isCurrent: Bool
    var p: CardsPalette
    var t: CardsType
    var marks: Int

    var body: some View {
        let nodes = FleetSection.troubleFirst(groups)
        HStack(spacing: 6) {
            Color.clear.frame(width: 14 * t.scale, height: 1)
            Text(tr("+\(groups.count) more")).font(t.font(12)).foregroundStyle(p.l2).lineLimit(1)
            Spacer(minLength: 3)
            HStack(spacing: 2.5) {
                ForEach(nodes.prefix(marks)) { n in CardMark(mark: n.mark, size: 8, color: p.listColor(n.mark)) }
                if nodes.count > marks {
                    Text(verbatim: "+\(nodes.count - marks)").font(t.font(10)).foregroundStyle(p.l3).padding(.leading, 1)
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isCurrent ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tr("+\(groups.count) more") + ": " + groups.map { FleetCell.nodes($0) }.joined(separator: " · ")))
    }
}

/// One provider's servers, or one edge, platform or lone node: who, and a
/// mark for each node.
struct FleetCell: View {
    var group: FleetSection.Group
    var isCurrent: Bool
    var p: CardsPalette
    var t: CardsType
    var marks: Int

    var body: some View {
        HStack(spacing: 6) {
            FleetGlyph(group: group, p: p, size: 14 * t.scale)
            // What an edge is goes first when the name needs the room.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    title.fixedSize()
                    if group.isEdge {
                        Text(Words.kind(group.kind)).font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).fixedSize()
                    }
                }
                title
            }
            Spacer(minLength: 3)
            HStack(spacing: 2.5) {
                ForEach(group.nodes.prefix(marks)) { n in CardMark(mark: n.mark, size: 8, color: p.listColor(n.mark)) }
                if group.nodes.count > marks {
                    Text(verbatim: "+\(group.nodes.count - marks)").font(t.font(10)).foregroundStyle(p.l3).padding(.leading, 1)
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isCurrent ? 1 : 0.55)
        .help(Self.nodes(group))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Words.join([group.title, group.isEdge ? Words.kind(group.kind) : ""]) + ": " + Self.nodes(group)))
    }

    var title: some View {
        Text(group.title).font(t.font(12)).foregroundStyle(p.l1).lineLimit(1).truncationMode(.tail)
    }

    /// "Oracle LA, up · Oracle New York, warn, affected".
    static func nodes(_ group: FleetSection.Group) -> String {
        group.nodes.map { n in [n.name, n.mark.word, n.note].filter { !$0.isEmpty }.joined(separator: ", ") }
            .joined(separator: " · ")
    }
}

/// Who runs a group, small: the provider's logo, its kind's glyph where
/// there's no logo, or a lone node's kind.
struct FleetGlyph: View {
    var group: FleetSection.Group
    var p: CardsPalette
    var size: Double

    var body: some View {
        Group {
            if let key = ProviderLogo.key(provider: group.provider, kind: group.kind) {
                ProviderGlyph(key: key, color: p.l2)
            } else {
                Image(systemName: NodeAvatar.symbol(group.kind)).font(.system(size: size * 0.78)).foregroundStyle(p.l2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
