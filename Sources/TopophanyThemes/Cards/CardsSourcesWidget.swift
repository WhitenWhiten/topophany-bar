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
    /// Japanese and Chinese break between any two characters, so a word
    /// joiner holds each pair of a part together.
    var subtitle: String {
        status.subtitle.components(separatedBy: " · ")
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}").map(String.init).joined(separator: "\u{2060}") }
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
                        sourceList(most: 8)
                    } else {
                        WidgetResources(cards: servers, meters: false, p: p, t: t)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case .large:
            VStack(alignment: .leading, spacing: 0) {
                big
                if servers.isEmpty {
                    // Nothing pinned: the servers as a bar, then each source
                    // with what it says.
                    bar.padding(.top, 12)
                    gap
                    hinted(sourceList(most: 8))
                } else {
                    // The sources first: what one asks for outranks tiles.
                    rows(detail: true, most: 3).padding(.top, 10).layoutPriority(2)
                    gap
                    // Tiles while every server fits as one, a row each past that.
                    ViewThatFits(in: .vertical) {
                        WidgetServerTiles(cards: servers, columns: 1, style: .sizes, p: p, t: t)
                        WidgetServerTiles(cards: servers, columns: 2, style: .meters, p: p, t: t)
                        WidgetServerTiles(cards: servers, columns: 2, style: .dense, p: p, t: t)
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
                    tiles(columns: 2, style: .sizes)
                    tiles(columns: 4, style: .meters)
                    tiles(columns: 4, style: .dense)
                    columns
                }
            }
        }
    }

    /// The state and its sources over the servers' tiles, across the
    /// widget.
    func tiles(columns: Int, style: WidgetServerTiles.Style) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                big.frame(maxWidth: .infinity)
                rows(detail: true, most: 3).frame(maxWidth: .infinity)
            }
            gap
            WidgetServerTiles(cards: servers, columns: columns, style: style, p: p, t: t)
            Spacer(minLength: 8)
            foot(wide: true)
        }
    }

    /// The state and its sources beside the servers' rows: for more
    /// servers than tiles can hold. With none pinned, the sources take the
    /// right, each with what it says.
    var columns: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                big
                bar.padding(.top, 12)
                if !servers.isEmpty { rows(detail: true, most: 8).padding(.top, 12) }
                Spacer(minLength: 8)
                foot(wide: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Group {
                if servers.isEmpty { hinted(sourceList(most: 12)) } else { WidgetResources(cards: servers, meters: true, p: p, t: t) }
            }
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
                .padding(.top, 2).padding(.bottom, 9)
            bar.padding(.bottom, 8)
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

    /// Every selected server, as the collector's bar draws checks.
    var bar: some View { serverBar(sources.value.counts) }

    /// Servers a tick each: current calm, the rest (stale, without
    /// samples) outlined. Hatched once the snapshot isn't current or
    /// `topo` gave no counts.
    @ViewBuilder func serverBar(_ counts: SourcesStatus.Counts?, ticks: Double = StackBar.tickHeight) -> some View {
        if sources.isCurrent, let n = Self.split(counts) {
            StackBar(counts: (n.current, 0, 0, n.rest), palette: p, height: min(6, ticks),
                     vibrant: ctx.widgetRendering == .vibrant, ticks: ticks)
                .accessibilityHidden(true)
        } else {
            Hatch(color: p.fill, line: 3, gap: 3)
                .frame(height: min(6, ticks))
                .clipShape(Capsule())
                .frame(height: ticks)
                .accessibilityHidden(true)
        }
    }

    /// Servers as `topo` counts them, current and the rest; `nil` with
    /// none to draw.
    static func split(_ c: SourcesStatus.Counts?) -> (current: Int, rest: Int)? {
        guard let c, let current = c.current else { return nil }
        let total = max(current, c.selected ?? current + (c.stale ?? 0) + (c.missing ?? 0))
        return total > 0 ? (current, total - current) : nil
    }

    /// `list`, and under it where to pin servers to see them here, while
    /// both fit.
    func hinted(_ list: some View) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 14) {
                list
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "pin").font(.system(size: 9.5))
                    Text(tr("Pin servers in Settings › Sections to show their readings here."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(t.font(10.5)).foregroundStyle(p.l3)
            }
            list
        }
    }

    /// Every source under its heading, with what each says, and each
    /// over its own servers' bar while all fit so.
    func sourceList(most: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "externaldrive.connected.to.line.below", title: tr("Sources"),
                          meta: "\(sources.value.sources.count)", p: p, t: t)
            rows(detail: true, most: most, bars: true)
        }
    }

    /// As many sources as fit, at most `most`; those left out are counted.
    /// Where none fits, none is drawn: the foot counts them. With `bars`,
    /// first every source over its servers' bar.
    func rows(detail: Bool, most: Int = 8, bars: Bool = false) -> some View {
        let list = sources.value.sources
        let top = min(most, list.count)
        let options = (bars && top == list.count ? [(n: top, bars: true)] : [])
            + stride(from: top, through: 0, by: -1).map { (n: $0, bars: false) }
        return ViewThatFits(in: .vertical) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                VStack(alignment: .leading, spacing: o.bars ? 9 : 4) {
                    ForEach(list.prefix(o.n)) { s in
                        VStack(alignment: .leading, spacing: 5) {
                            row(s, detail: detail)
                            if o.bars { serverBar(s.counts, ticks: 5).padding(.leading, 14) }
                        }
                    }
                    if list.count > o.n, o.n > 0 {
                        Text(tr("+\(list.count - o.n) more")).font(t.font(11)).foregroundStyle(p.l3).lineLimit(1)
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
/// readings as its style draws them. Drawn only where every server fits.
struct WidgetServerTiles: View {
    enum Style {
        /// A meter a row, and what each measures.
        case sizes
        /// A meter a row.
        case meters
        /// The three side by side, each value over its meter, labelled
        /// once over each column of tiles: for more servers than rows of
        /// meters hold.
        case dense
    }

    /// The labels, in the order every tile draws its readings.
    static var labels: [String] { [tr("CPU"), tr("Mem"), tr("Disk")] }
    /// Between a dense tile's readings.
    static let spacing = 10.0
    static let inset = EdgeInsets(top: 7, leading: 9, bottom: 8, trailing: 9)
    static let denseInset = EdgeInsets(top: 6, leading: 9, bottom: 7, trailing: 9)

    var cards: [ServerCardModel]
    var columns: Int
    var style: Style
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        // A tile names its source only where that tells servers apart.
        let sources = Set(cards.compactMap(\.origin?.sourceID)).count > 1
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: "server.rack", title: tr("Servers"), meta: "\(cards.count)", p: p, t: t)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                if style == .dense {
                    GridRow {
                        ForEach(0..<min(columns, cards.count), id: \.self) { _ in legend }
                    }
                    .padding(.bottom, -5)
                }
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
            // A server with nothing current says why, where its source would
            // be, while its name fits whole beside it: its meters are
            // hatched alike either way.
            ViewThatFits(in: .horizontal) {
                if c.hasNoCurrentSample { header(c, source: source, state: true) }
                header(c, source: source, state: false)
            }
            if style == .dense {
                HStack(alignment: .top, spacing: Self.spacing) {
                    gauge(Self.labels[0], c.cpu)
                    gauge(Self.labels[1], c.memory)
                    gauge(Self.labels[2], c.disk)
                }
                .padding(.top, 5)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 5) {
                    WidgetMeter(label: tr("CPU"), meter: c.cpu, p: p, t: t, size: style == .sizes).row
                    WidgetMeter(label: tr("Mem"), meter: c.memory, p: p, t: t, size: style == .sizes).row
                    WidgetMeter(label: tr("Disk"), meter: c.disk, p: p, t: t, size: style == .sizes).row
                }
                .padding(.top, 6)
            }
        }
        .padding(style == .dense ? Self.denseInset : Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { TileGround(p: p) }
        .accessibilityElement(children: .combine)
    }

    /// Over a column of dense tiles, each label over its readings.
    var legend: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Self.labels, id: \.self) { label in
                Text(label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(t.font(9.5)).foregroundStyle(p.l3)
        .padding(.horizontal, Self.inset.leading)
        .accessibilityHidden(true)
    }

    func header(_ c: ServerCardModel, source: Bool, state: Bool) -> some View {
        HStack(spacing: 6) {
            CardMark(mark: c.mark, size: 8, color: p.listColor(c.mark))
            Text(c.name).font(t.font(11.5, .semibold)).foregroundStyle(p.l1).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 6)
            if state {
                PillView(pill: c.pill, palette: p, type: t, plain: true)
            } else if source, let name = c.origin?.name {
                Text(name).font(t.font(10)).foregroundStyle(p.l3).lineLimit(1)
            }
        }
    }

    /// A dense tile's reading: its value over its meter, its label in
    /// the legend above.
    func gauge(_ label: String, _ m: ServerCardModel.Meter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.percent.map { Words.percent($0, digits: 0) } ?? "—")
                .font(t.mono(11, .semibold)).foregroundStyle(m.percent == nil ? p.l3 : p.l1).lineLimit(1)
            Meter(percent: m.percent, limit: m.limit, palette: p, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(m.percent.map { "\(label) \(Words.percent($0, digits: 0))" } ?? "\(label) \(tr("unknown"))"))
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
                    if c.hasNoCurrentSample {
                        // Why there are no values, ending where they would:
                        // drawn leftwards from the last column, so it widens
                        // none of them.
                        Color.clear.frame(width: 0, height: 0)
                        Color.clear.frame(width: 0, height: 0)
                        PillView(pill: c.pill, palette: p, type: t, plain: true)
                            .frame(width: 0, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                    } else {
                        value(c.cpu)
                        value(c.memory)
                        value(c.disk)
                    }
                }
                .font(t.font(11.5))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(c.hasNoCurrentSample ? Words.join([c.name, c.pill.text])
                                         : Words.join([c.name, spoken(tr("CPU"), c.cpu), spoken(tr("Mem"), c.memory), spoken(tr("Disk"), c.disk)])))
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
