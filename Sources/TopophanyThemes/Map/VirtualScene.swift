import CoreGraphics
import Foundation
import TopophanySections

/// The virtual geo map laid out, as the TUI's virtual map lays it out
/// (internal/tui/virtual_layout.go): each place a card with a row per node,
/// in columns west to east along the shortest arc of longitude that holds
/// them all, north above south; a node without a place a pill beside the
/// cards it links to; and a wire per line between two cards' rows. Shared by
/// both renderers, in their units.
struct VirtualScene {
    /// What a renderer's cards measure.
    struct Metrics {
        /// A card's title, and each row.
        var title: Double
        var row: Double
        /// Inside a card, across and down.
        var padX: Double
        var padY: Double
        /// A pill's height.
        var pill: Double
        /// Between a row's mark and its name, the mark included; and a
        /// child's indent.
        var mark: Double
        var indent: Double
        var minWidth: Double
        var maxWidth: Double
        /// The least between columns, and between cards in one.
        var colGap: Double
        var cardGap: Double
        /// Around the whole.
        var margin: Double
        /// A chip's marks, one per node.
        var chipMark: Double = 9
        /// Between columns of tiles or chips.
        var compactGap: Double = 12
        /// Whether a card may fold to a tile before it folds to a chip.
        var tiles = true
    }

    struct Row {
        var node: MapSection.Node
        var depth: Int
        /// The row's middle, down from the card's top.
        var y: Double
    }

    struct Card {
        /// The place; empty for a node without one.
        var title: String
        var rows: [Row]
        /// Rows folded away for room, counted on the card's last line.
        var folded: [MapSection.Node] = []
        /// Folded to one line: its place and a mark per node.
        var isChip = false
        /// Folded to two: its place over a mark per node.
        var isTile = false
        var rect: CGRect = .zero
        var isPill: Bool
        var lat = 0.0
        var lon = 0.0
        var located: Bool
        var col = 0
        var natural = 0.0
        var want = 0.0

        /// Every node on it, folded or not.
        var nodes: [MapSection.Node] { rows.map(\.node) + folded }
        /// What needs the most attention on it.
        var mark: Mark { nodes.map(\.mark).reduce(Mark.offline) { GeoScene.worse($0, $1, first: $0 == .offline) } }
    }

    struct Wire {
        var from: CGPoint
        var to: CGPoint
        /// Which way each end leaves its card: 1 to the right, -1 to the left.
        var fromSide: Double
        var toSide: Double
        var line: MapSection.Line
        var declared: Bool
    }

    /// How much each card says: every row, a few rows, its place over its
    /// marks, or both on one line.
    enum Detail: CaseIterable {
        case rows, folded, tiles, chips

        var compact: Bool { self == .tiles || self == .chips }
    }

    var cards: [Card] = []
    var wires: [Wire] = []
    /// How much room it takes, at its own size.
    var extent: CGSize = .zero
    var detail = Detail.rows
    /// A chip's marks: how many before the rest are counted.
    static let chipMarks = 6

    init(_ map: MapSection, size: CGSize, metrics m: Metrics, measure: (String, _ title: Bool) -> Double) {
        let nodes = map.nodes
        var idx: [String: Int] = [:]
        for (i, n) in nodes.enumerated() { idx[n.id] = i }

        // Cards: located nodes by place, or close enough to share one; the
        // rest by the root they hang from.
        var base: [Card] = []
        var anchor: [Int: MapSection.Coordinate] = [:]
        var members: [[Int]] = []
        var byRoot: [String: Int] = [:]
        for (i, n) in nodes.enumerated() {
            if let c = n.coordinate {
                let k = base.indices.first { k in
                    guard let a = anchor[k] else { return false }
                    let dLat = abs(a.lat - c.lat), dLon = abs(Self.lonDiff(a.lon, c.lon))
                    return (!n.place.isEmpty && n.place == base[k].title && dLat < 3 && dLon < 3) || (dLat < 0.5 && dLon < 0.5)
                }
                if let k {
                    members[k].append(i)
                    if base[k].title.isEmpty && !n.isColo { base[k].title = n.place }
                } else {
                    base.append(Card(title: n.isColo ? "" : n.place, rows: [], isPill: false, located: true))
                    anchor[base.count - 1] = c
                    members.append([i])
                }
                continue
            }
            var root = n.id
            var parent = n.parent
            for _ in 0..<16 where !parent.isEmpty {
                guard let j = idx[parent], nodes[j].coordinate == nil else { break }
                root = parent
                parent = nodes[j].parent
            }
            if let k = byRoot[root] {
                members[k].append(i)
            } else {
                byRoot[root] = base.count
                base.append(Card(title: "", rows: [], isPill: false, located: false))
                members.append([i])
            }
        }
        for k in base.indices {
            let ns = members[k].map { nodes[$0] }
            if base[k].located {
                let cs = ns.compactMap(\.coordinate)
                let a = anchor[k] ?? cs[0]
                base[k].lat = cs.map(\.lat).reduce(0, +) / Double(cs.count)
                base[k].lon = a.lon + cs.map { Self.lonDiff(a.lon, $0.lon) }.reduce(0, +) / Double(cs.count)
                if base[k].title.isEmpty { base[k].title = ns.first { !$0.place.isEmpty }?.place ?? "" }
            }
            // Children under their parents, as the card's rows.
            var rows: [Row] = []
            let ids = Set(ns.map(\.id))
            func add(_ n: MapSection.Node, _ depth: Int) {
                guard !rows.contains(where: { $0.node.id == n.id }) else { return }
                rows.append(Row(node: n, depth: depth, y: 0))
                for c in ns where c.parent == n.id { add(c, min(depth + 1, 3)) }
            }
            for n in ns where n.parent.isEmpty || !ids.contains(n.parent) { add(n, 0) }
            for n in ns { add(n, 0) }
            base[k].rows = rows
            base[k].isPill = !base[k].located && rows.count == 1
        }
        guard !base.isEmpty else { return }

        // Who links to whom, card to card.
        var cardOf: [String: Int] = [:]
        for (k, c) in base.enumerated() { for r in c.rows { cardOf[r.node.id] = k } }
        var near: [[Int]] = Array(repeating: [], count: base.count)
        for e in map.edges {
            guard let a = cardOf[e.from], let b = cardOf[e.to], a != b else { continue }
            near[a].append(b)
            near[b].append(a)
        }

        // Places west to east along the shortest arc of longitude holding
        // them; when the width runs short, the closest share a column.
        let places = base.indices.filter { base[$0].located }
        let (centre, arc) = GeoView.lonBounds(places.map { base[$0].lon })
        let key = { (k: Int) -> Double in ((base[k].lon - (centre - arc / 2) + 720 + 1e-6).truncatingRemainder(dividingBy: 360)) }
        let order = places.sorted { key($0) < key($1) }
        let gaps = order.count > 1
            ? (0..<(order.count - 1)).sorted { key(order[$0 + 1]) - key(order[$0]) > key(order[$1 + 1]) - key(order[$1]) } : []
        func split(_ nc: Int) -> [Int: Int] {
            let cuts = Set(gaps.prefix(max(0, nc - 1)).map { $0 + 1 })
            var col = 0
            var out: [Int: Int] = [:]
            for (i, k) in order.enumerated() {
                if cuts.contains(i) { col += 1 }
                out[k] = col
            }
            return out
        }
        func height(_ c: Card) -> Double {
            if c.isPill || c.isChip { return m.pill }
            if c.isTile { return m.title + m.row + 2 * m.padY - 2 }
            let lines = Double(c.rows.count + (c.folded.isEmpty ? 0 : 1))
            return (c.title.isEmpty ? 0 : m.title) + lines * m.row + 2 * m.padY
        }
        let room = size.height - 2 * m.margin

        // The most each card can say and still have every column fit: every
        // row, then a few, then one line each.
        var cards = base
        var cols = 1
        for detail in Detail.allCases where m.tiles || detail != .tiles {
            var said = base
            for k in said.indices { Self.apply(detail, to: &said[k], metrics: m, measure: measure) }
            let colGap = detail.compact ? m.compactGap : m.colGap
            // As many columns as the width holds, cards without a place
            // counted where they join.
            for nc in stride(from: max(1, order.count), through: 1, by: -1) {
                cards = said
                for (k, c) in split(nc) { cards[k].col = c }
                Self.joinNeighbours(&cards, near: near, cols: nc, room: room + m.cardGap) { height($0) + m.cardGap }
                var w = Array(repeating: 0.0, count: nc)
                for c in cards { w[c.col] = max(w[c.col], c.natural) }
                cols = nc
                if w.reduce(0, +) + Double(nc - 1) * colGap + 2 * m.margin <= size.width { break }
            }
            let tallest = (0..<cols).map { col in
                let list = cards.filter { $0.col == col }
                return list.map(height).reduce(0, +) + Double(max(0, list.count - 1)) * m.cardGap
            }.max() ?? 0
            self.detail = detail
            if tallest <= room { break }
        }

        // Columns as wide as their widest card; the widest give way first.
        let colGap = detail.compact ? m.compactGap : m.colGap
        var colW = Array(repeating: 0.0, count: cols)
        for c in cards { colW[c.col] = max(colW[c.col], c.natural) }
        while colW.reduce(0, +) + Double(cols - 1) * colGap + 2 * m.margin > size.width,
              let wide = colW.indices.max(by: { colW[$0] < colW[$1] }), colW[wide] > m.minWidth {
            colW[wide] = max(m.minWidth, colW[wide] - 1)
        }
        let spare = max(0, size.width - colW.reduce(0, +) - 2 * m.margin)
        let gap = cols > 1 ? spare / Double(cols - 1) : 0
        var colX: [Double] = []
        var x = cols > 1 ? m.margin : (size.width - colW[0]) / 2
        for w in colW {
            colX.append(x)
            x += w + gap
        }
        for k in cards.indices {
            let w = min(cards[k].natural, colW[cards[k].col])
            cards[k].rect = CGRect(x: colX[cards[k].col] + (colW[cards[k].col] - w) / 2, y: 0, width: w, height: height(cards[k]))
        }

        // Latitude orders each column and loosely sets its height: halfway
        // between even ranks and true proportion. A card without a place
        // moves toward the cards it links to.
        let lats = places.map { cards[$0].lat }.sorted(by: >)
        for k in cards.indices {
            cards[k].want = (room - cards[k].rect.height) / 2
            if cards[k].located, let top = lats.first, let bottom = lats.last, top > bottom {
                let rank = Double(lats.firstIndex { $0 <= cards[k].lat } ?? 0)
                let t = rank / Double(lats.count - 1) / 2 + (top - cards[k].lat) / (top - bottom) / 2
                cards[k].want = t * (room - cards[k].rect.height)
            }
        }
        for _ in 0..<6 {
            for col in 0..<cols { Self.pack(&cards, cards.indices.filter { cards[$0].col == col }, room: room, gap: m.cardGap) }
            for k in cards.indices where !cards[k].located {
                let linked = near[k].filter { cards[$0].col != cards[k].col || cards[$0].located }
                guard !linked.isEmpty else { continue }
                cards[k].want = linked.map { cards[$0].rect.midY }.reduce(0, +) / Double(linked.count) - cards[k].rect.height / 2
            }
        }
        var bottom = 0.0
        for k in cards.indices {
            cards[k].rect.origin.y += m.margin
            bottom = max(bottom, cards[k].rect.maxY)
            var y = m.padY + (cards[k].title.isEmpty ? 0 : m.title) + m.row / 2
            for r in cards[k].rows.indices {
                cards[k].rows[r].y = cards[k].isPill || cards[k].isChip || cards[k].isTile ? cards[k].rect.height / 2 : y
                y += m.row
            }
        }
        self.cards = cards
        extent = CGSize(width: size.width, height: max(size.height, bottom + m.margin))

        // A wire per line between two cards, from the row of one end to the
        // row of the other, the worst line where two share both rows; or,
        // with cards folded to a line or two, one per pair of cards.
        var rowAt: [String: (card: Int, y: Double)] = [:]
        for (k, c) in cards.enumerated() {
            for r in c.rows { rowAt[r.node.id] = (k, c.rect.minY + r.y) }
            // Folded rows meet the card at its last line.
            for n in c.folded { rowAt[n.id] = (k, c.isChip || c.isTile ? c.rect.midY : c.rect.maxY - m.padY - m.row / 2) }
        }
        struct End: Hashable { var card: Int; var side: Double }
        var seen: [String: Int] = [:]
        var ends: [(wire: Int, from: Bool, end: End, toward: Double)] = []
        for e in map.edges {
            guard let a = rowAt[e.from], let b = rowAt[e.to], a.card != b.card else { continue }
            let A = cards[a.card].rect, B = cards[b.card].rect
            let fromSide: Double, toSide: Double
            if abs(A.midX - B.midX) < 1 {
                // In one column: out and back on the side with more room.
                let side: Double = cards[a.card].col == cols - 1 && cols > 1 ? -1 : 1
                (fromSide, toSide) = (side, side)
            } else {
                (fromSide, toSide) = A.midX < B.midX ? (1, -1) : (-1, 1)
            }
            let from = CGPoint(x: fromSide > 0 ? A.maxX : A.minX, y: a.y)
            let to = CGPoint(x: toSide > 0 ? B.maxX : B.minX, y: b.y)
            let key = detail.compact ? "\(min(a.card, b.card))-\(max(a.card, b.card))"
                : "\(Int(from.x)),\(Int(from.y))-\(Int(to.x)),\(Int(to.y))"
            if let i = seen[key] {
                if e.line.rank > wires[i].line.rank { wires[i].line = e.line }
                wires[i].declared = wires[i].declared || e.kind == .link
                continue
            }
            seen[key] = wires.count
            ends.append((wires.count, true, End(card: a.card, side: fromSide), b.y))
            ends.append((wires.count, false, End(card: b.card, side: toSide), a.y))
            wires.append(Wire(from: from, to: to, fromSide: fromSide, toSide: toSide, line: e.line, declared: e.kind == .link))
        }
        // On a card of a line or two, the wires that leave one side spread
        // along it, in the order of where they go, so none run together.
        if detail.compact {
            for (end, list) in Dictionary(grouping: ends, by: \.end) where list.count > 1 {
                let r = cards[end.card].rect
                let span = min(r.height - 6, Double(list.count - 1) * 3.5)
                for (i, e) in list.sorted(by: { $0.toward < $1.toward }).enumerated() {
                    let y = r.midY - span / 2 + span * Double(i) / Double(list.count - 1)
                    if e.from { wires[e.wire].from.y = y } else { wires[e.wire].to.y = y }
                }
            }
        }
    }

    /// What a card says at `detail`, and how wide that is.
    static func apply(_ detail: Detail, to c: inout Card, metrics m: Metrics, measure: (String, Bool) -> Double) {
        func rowWidth(_ r: Row) -> Double { m.indent * Double(r.depth) + m.mark + measure(r.node.name, false) }
        if c.isPill {
            c.natural = min(m.maxWidth, (c.rows.first.map(rowWidth) ?? 0) + 2 * m.padX)
            return
        }
        let titleW = c.title.isEmpty ? 0 : measure(c.title, true)
        switch detail {
        case .rows:
            break
        case .folded where c.rows.count > 3:
            // Trouble stays; what folds is counted, its marks kept.
            let kept = Set(Mark.troubleFirst(c.rows, by: \.node.mark).prefix(2).map(\.node.id))
            c.folded = c.rows.filter { !kept.contains($0.node.id) }.map(\.node)
            c.rows = c.rows.filter { kept.contains($0.node.id) }
        case .folded:
            break
        case .tiles where !c.title.isEmpty:
            c.isTile = true
            let marks = min(c.rows.count, chipMarks)
            let more = c.rows.count > chipMarks ? measure("+\(c.rows.count - chipMarks)", false) + 2 : 0
            c.natural = min(m.maxWidth, max(titleW, Double(marks) * m.chipMark + more) + 2 * m.padX)
            return
        case .tiles, .chips:
            c.isChip = true
            let marks = min(c.rows.count, chipMarks)
            let more = c.rows.count > chipMarks ? measure("+\(c.rows.count - chipMarks)", false) + 2 : 0
            let label = c.title.isEmpty ? measure(c.rows.first?.node.name ?? "", false) : titleW
            c.natural = min(m.maxWidth, label + 5 + Double(marks) * m.chipMark + more + 2 * m.padX)
            return
        }
        let rowW = c.rows.map(rowWidth).max() ?? 0
        c.natural = min(m.maxWidth, max(m.minWidth, max(rowW, titleW) + 2 * m.padX))
    }

    /// Cards without a place join the column their neighbours average,
    /// counting other such cards at half weight, or with none, the last; or
    /// the nearest to that with `room` left for them.
    static func joinNeighbours(_ cards: inout [Card], near: [[Int]], cols: Int, room: Double, height: (Card) -> Double) {
        var colAt = cards.map { $0.located ? Double($0.col) : -1 }
        for it in 0..<6 {
            for k in cards.indices where !cards[k].located {
                var sum = 0.0, n = 0.0
                for o in near[k] {
                    if cards[o].located {
                        sum += colAt[o]
                        n += 1
                    } else if colAt[o] >= 0 {
                        sum += colAt[o] / 2
                        n += 0.5
                    }
                }
                if n > 0 { colAt[k] = sum / n } else if it == 5 || colAt[k] < 0 { colAt[k] = Double(cols - 1) }
            }
        }
        var used = Array(repeating: 0.0, count: cols)
        for c in cards where c.located { used[c.col] += height(c) }
        for k in cards.indices where !cards[k].located {
            let want = min(max(colAt[k], 0), Double(cols - 1))
            let byNearness = (0..<cols).sorted { abs(Double($0) - want) < abs(Double($1) - want) }
            let h = height(cards[k])
            let col = byNearness.first { used[$0] + h <= room } ?? byNearness[0]
            cards[k].col = col
            used[col] += h
        }
    }

    /// Stacks a column's cards in the order of the heights they want, `gap`
    /// apart at least, each as near its wish as the others allow.
    static func pack(_ cards: inout [Card], _ list: [Int], room: Double, gap: Double) {
        let sorted = list.sorted { cards[$0].want < cards[$1].want }
        // Taller than the room: one under another, and the whole map is
        // drawn smaller.
        guard sorted.map({ cards[$0].rect.height }).reduce(0, +) + Double(max(0, sorted.count - 1)) * gap <= room else {
            var y = 0.0
            for k in sorted {
                cards[k].rect.origin.y = y
                y += cards[k].rect.height + gap
            }
            return
        }
        var y = -Double.infinity
        for k in sorted {
            let top = max(cards[k].want, y)
            cards[k].rect.origin.y = max(0, top)
            y = cards[k].rect.origin.y + cards[k].rect.height + gap
        }
        // Back up from the bottom where the column runs past it.
        var limit = room
        for k in sorted.reversed() {
            cards[k].rect.origin.y = max(0, min(cards[k].rect.origin.y, limit - cards[k].rect.height))
            limit = cards[k].rect.origin.y - gap
        }
    }

    static func lonDiff(_ a: Double, _ b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// A wire's path: out of its card level, in a curve, and level again
    /// into the other.
    func control(_ w: Wire) -> (CGPoint, CGPoint) {
        let dx = abs(w.to.x - w.from.x)
        let k = max(14, dx * 0.45)
        return (CGPoint(x: w.from.x + w.fromSide * k, y: w.from.y), CGPoint(x: w.to.x + w.toSide * k, y: w.to.y))
    }
}
