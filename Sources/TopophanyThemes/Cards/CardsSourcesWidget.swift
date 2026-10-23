import Foundation
import SwiftUI
import TopophanyKit
import TopophanySections

/// A Status widget in direct mode: the sources' state as of when it was
/// read, each source, and where there's room the pinned servers'
/// readings. Nothing in it renews itself: past its deadlines it is history.
struct WidgetSources: View {
    var model: WidgetModel
    var sources: SourceStatusSection
    var size: WidgetSize
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext

    var status: StatusSection { model.status }
    var servers: [ServerCardModel] { model.panel.servers }

    /// "2 of 4 current · 1 stale · 1 without samples", wrapping only
    /// between its parts: each kept whole, a "·" never starting a line.
    var subtitle: String {
        status.subtitle.components(separatedBy: " · ").map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: "\u{00A0}· ")
    }

    var body: some View {
        switch size {
        case .small:
            narrow
        case .medium:
            HStack(alignment: .top, spacing: 16) {
                narrow.frame(width: 136)
                Group {
                    if servers.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            WidgetHeading(symbol: "externaldrive.connected.to.line.below", title: tr("Sources"),
                                          meta: "\(sources.value.sources.count)", p: p, t: t)
                            rows(detail: true)
                        }
                    } else {
                        WidgetResources(cards: servers, meters: false, p: p, t: t)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case .large:
            VStack(alignment: .leading, spacing: 0) {
                big
                rows(detail: true, most: 3).padding(.top, 10)
                if !servers.isEmpty {
                    gap
                    // Tiles while every server fits as one, a row each past that.
                    ViewThatFits(in: .vertical) {
                        WidgetServerTiles(cards: servers, columns: 1, sizes: true, p: p, t: t)
                        WidgetServerTiles(cards: servers, columns: 2, sizes: false, p: p, t: t)
                        WidgetResources(cards: servers, meters: true, p: p, t: t)
                    }
                    .layoutPriority(1)
                }
                Spacer(minLength: 8)
                foot(wide: true)
            }
        case .extraLarge:
            if servers.isEmpty {
                columns
            } else {
                ViewThatFits(in: .vertical) {
                    tiles(columns: 2, sizes: true)
                    tiles(columns: 4, sizes: false)
                    columns
                }
            }
        }
    }

    /// The state and its sources over the servers' tiles, across the
    /// widget.
    func tiles(columns: Int, sizes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                big.frame(maxWidth: .infinity)
                rows(detail: true, most: 3).frame(maxWidth: .infinity)
            }
            gap
            WidgetServerTiles(cards: servers, columns: columns, sizes: sizes, p: p, t: t)
            Spacer(minLength: 8)
            foot(wide: true)
        }
    }

    /// The state and its sources beside the servers' rows: for more
    /// servers than tiles can hold.
    var columns: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                big
                rows(detail: true, most: 8).padding(.top, 10)
                Spacer(minLength: 8)
                foot(wide: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            WidgetResources(cards: servers, meters: true, p: p, t: t)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Between blocks, as the collector's widgets space theirs.
    var gap: some View { Spacer(minLength: 12).frame(maxHeight: 20) }

    /// The state in a narrow column, its sources in the room left.
    var narrow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                HeroSymbol(status: status, size: 34, palette: p)
                Spacer(minLength: 0)
                WidgetMark(palette: p, rendering: ctx.widgetRendering)
            }
            Text(status.title).font(t.font(16, .semibold)).tracking(-0.24).lineLimit(1)
                .padding(.top, 10)
            Text(subtitle).font(t.font(11)).foregroundStyle(p.l2).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2).padding(.bottom, 8)
            if size == .small { rows(detail: false) }
            Spacer(minLength: 0)
            foot(wide: false)
        }
    }

    var big: some View {
        HStack(spacing: 12) {
            HeroSymbol(status: status, size: 44, palette: p)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(t.font(18, .semibold)).tracking(-0.27).lineLimit(1)
                Text(subtitle).font(t.font(11)).foregroundStyle(p.l2).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            WidgetMark(palette: p, rendering: ctx.widgetRendering)
        }
        .accessibilityElement(children: .combine)
    }

    /// As many sources as fit, at most `most`; those left out are counted.
    /// Where none fits, none is drawn: the foot counts them.
    func rows(detail: Bool, most: Int = 8) -> some View {
        let list = sources.value.sources
        return ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: min(most, list.count), through: 0, by: -1)), id: \.self) { n in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(list.prefix(n)) { s in row(s, detail: detail) }
                    if list.count > n, n > 0 {
                        Text(tr("+\(list.count - n) more")).font(t.font(11)).foregroundStyle(p.l3).lineLimit(1)
                            .padding(.leading, 14)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func row(_ s: SourcesStatus.Source, detail: Bool) -> some View {
        let m = sources.mark(s)
        let look = sources.needsLook(s)
        return HStack(spacing: 6) {
            CardMark(mark: m, size: 8, color: p.listColor(m))
            Text(s.name).foregroundStyle(p.l1).lineLimit(1).truncationMode(.middle)
            if detail {
                Spacer(minLength: 6)
                Text(sources.detail(s)).font(t.font(10.5, look ? .semibold : .regular)).foregroundStyle(look ? p.l1 : p.l3)
                    .lineLimit(1).fixedSize()
            }
        }
        .font(t.font(11.5))
        .accessibilityElement(children: .combine)
    }

    /// How many sources, and when the snapshot was read: never an age
    /// that counts up, since a new hand-off can't renew it.
    func foot(wide: Bool) -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "externaldrive.connected.to.line.below").font(.system(size: 10))
                Text(wide ? sources.sourceCount : "\(sources.value.counts?.sources ?? sources.value.sources.count)")
            }
            Spacer(minLength: 4)
            if let at = sources.snapshotAt ?? model.updatedAt { Text(Words.asOf(at)) }
        }
        .font(t.font(10.5)).foregroundStyle(p.l3)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The pinned servers as tiles, `columns` to a row, each with its three
/// meters; a wide tile adds what each measures. Drawn only where every
/// server fits.
struct WidgetServerTiles: View {
    var cards: [ServerCardModel]
    var columns: Int
    var sizes: Bool
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        // A tile names its source only where that tells servers apart.
        let sources = Set(cards.compactMap(\.origin?.sourceID)).count > 1
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "server.rack", title: tr("Servers"), meta: "\(cards.count)", p: p, t: t)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: cards.count, by: columns)), id: \.self) { i in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { k in
                            if i + k < cards.count {
                                tile(cards[i + k], source: sources)
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    func tile(_ c: ServerCardModel, source: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                CardMark(mark: c.mark, size: 8, color: p.listColor(c.mark))
                Text(c.name).font(t.font(11.5, .semibold)).foregroundStyle(p.l1).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 6)
                if source, let name = c.origin?.name {
                    Text(name).font(t.font(10)).foregroundStyle(p.l3).lineLimit(1)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 5) {
                WidgetMeter(label: tr("CPU"), meter: c.cpu, p: p, t: t, size: sizes).row
                WidgetMeter(label: tr("Mem"), meter: c.memory, p: p, t: t, size: sizes).row
                WidgetMeter(label: tr("Disk"), meter: c.disk, p: p, t: t, size: sizes).row
            }
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 7, leading: 9, bottom: 8, trailing: 9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { TileGround(p: p) }
        .accessibilityElement(children: .combine)
    }
}

/// The pinned servers' readings, a row each: CPU, memory and disk as
/// their cards read them, "—" where withheld. As many as fit; the rest
/// are counted.
struct WidgetResources: View {
    var cards: [ServerCardModel]
    /// A short meter before each value, where the row has room for one.
    var meters: Bool
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "server.rack", title: tr("Servers"), meta: "\(cards.count)", p: p, t: t)
            ViewThatFits(in: .vertical) {
                ForEach(Array(stride(from: cards.count, through: 0, by: -1)), id: \.self) { n in
                    table(n).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func table(_ n: Int) -> some View {
        Grid(alignment: .leading, horizontalSpacing: meters ? 10 : 8, verticalSpacing: 5) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                label(tr("CPU"))
                label(tr("Mem"))
                label(tr("Disk"))
            }
            .font(t.font(9.5)).foregroundStyle(p.l3)
            ForEach(cards.prefix(n)) { c in
                GridRow {
                    HStack(spacing: 6) {
                        CardMark(mark: c.mark, size: 8, color: p.listColor(c.mark))
                        Text(c.name).foregroundStyle(p.l1).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    value(c.cpu)
                    value(c.memory)
                    value(c.disk)
                }
                .font(t.font(11.5))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Words.join([c.name, spoken(tr("CPU"), c.cpu), spoken(tr("Mem"), c.memory), spoken(tr("Disk"), c.disk)])))
            }
            if cards.count > n {
                GridRow {
                    Text(tr("+\(cards.count - n) more")).font(t.font(11)).foregroundStyle(p.l3).lineLimit(1).padding(.leading, 14)
                        .gridCellColumns(4)
                }
            }
        }
    }

    func spoken(_ label: String, _ m: ServerCardModel.Meter) -> String {
        "\(label) \(m.percent.map { Words.percent($0, digits: 0) } ?? tr("unknown"))"
    }

    /// A column's label, over its values' right edge.
    func label(_ s: String) -> some View {
        Text(s).lineLimit(1).fixedSize()
    }

    func value(_ m: ServerCardModel.Meter) -> some View {
        HStack(spacing: 5) {
            if meters { Meter(percent: m.percent, limit: m.limit, palette: p, height: 4).frame(width: 28) }
            Text(m.percent.map { Words.percent($0, digits: 0) } ?? "—")
                .font(t.mono(11, .semibold)).foregroundStyle(m.percent == nil ? p.l3 : p.l1)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .gridColumnAlignment(.trailing)
    }
}
