import Foundation
import TopophanySections

/// The Terminal look's virtual geo map, laid out on the cell grid: each
/// place one line, a chip of its name and a mark per node, in columns from
/// west to east and north to south down each; what has no place, a pill in
/// the column it links to most, where there's room. Every name stays whole:
/// columns merge before a name is cut, and only when one column can't hold
/// them are the last counted instead.
struct CellsVirtual {
    struct Card {
        /// The place, or for a pill its node's name.
        var title: String
        var nodes: [MapSection.Node]
        var isPill: Bool
        /// Counts the cards left out for room.
        var isMore = false
        var lat = 0.0
        var lon = 0.0
        var col = 0
        var row = 0
        /// Where it starts and how wide it is, in cells, its padding
        /// included.
        var x = 0
        var width = 0

        /// What needs the most attention on it.
        var mark: Mark { nodes.map(\.mark).reduce(Mark.offline) { GeoScene.worse($0, $1, first: $0 == .offline) } }
        /// Each node's mark, at most `CellsVirtual.marks`, the rest counted.
        var marks: (shown: [MapSection.Node], more: Int) {
            let shown = Array(nodes.prefix(nodes.count > CellsVirtual.marks ? CellsVirtual.marks - 1 : CellsVirtual.marks))
            return (shown, nodes.count - shown.count)
        }
    }

    struct Wire {
        var a: Int
        var b: Int
        var line: MapSection.Line
        var declared: Bool
    }

    /// A chip's marks before the rest are counted.
    static let marks = 4

    var cards: [Card] = []
    var wires: [Wire] = []
    /// Cards left out for want of room, counted at the foot.
    var leftOut: [MapSection.Node] = []

    init(_ map: MapSection, cols: Int, rows: Int) {
        guard cols > 4, rows > 0 else { return }
        // Places, each once; colos join the place they answered from.
        var cards: [Card] = []
        var cardOf: [String: Int] = [:]
        for n in map.nodes where !n.isColo {
            guard let c = n.coordinate else { continue }
            let k = cards.indices.first { k in
                (!n.place.isEmpty && cards[k].title == n.place)
                    || (abs(cards[k].lat - c.lat) < 0.5 && abs(VirtualScene.lonDiff(cards[k].lon, c.lon)) < 0.5)
            }
            if let k {
                cards[k].nodes.append(n)
                cardOf[n.id] = k
            } else {
                cardOf[n.id] = cards.count
                cards.append(Card(title: n.place.isEmpty ? GeoScene.coordinates(c) : n.place, nodes: [n], isPill: false,
                                  lat: c.lat, lon: c.lon))
            }
        }
        for n in map.nodes where n.isColo {
            guard let c = n.coordinate else { continue }
            cardOf[n.id] = cards.indices.first { cards[$0].title == n.place }
                ?? cards.indices.first { abs(cards[$0].lat - c.lat) < 1 && abs(VirtualScene.lonDiff(cards[$0].lon, c.lon)) < 1 }
        }
        // What has no place: a pill for each, its children folded in.
        var idx: [String: Int] = [:]
        for (i, n) in map.nodes.enumerated() { idx[n.id] = i }
        for n in map.nodes where n.coordinate == nil {
            var root = n
            for _ in 0..<16 {
                guard let j = idx[root.parent], map.nodes[j].coordinate == nil else { break }
                root = map.nodes[j]
            }
            if let k = cards.indices.first(where: { cards[$0].isPill && cards[$0].nodes[0].id == root.id }) {
                if n.id != root.id { cards[k].nodes.append(n) }
                cardOf[n.id] = k
            } else {
                cardOf[n.id] = cards.count
                cards.append(Card(title: root.name, nodes: n.id == root.id ? [n] : [root, n], isPill: true))
            }
        }
        guard !cards.isEmpty else { return }
        for k in cards.indices { cards[k].width = Self.width(cards[k]) }

        // One wire per pair of cards, the worst line between them.
        var pairs: [[Int]: Int] = [:]
        var wires: [Wire] = []
        for e in map.edges {
            guard let a = cardOf[e.from], let b = cardOf[e.to], a != b else { continue }
            let key = [min(a, b), max(a, b)]
            if let i = pairs[key] {
                if e.line.rank > wires[i].line.rank { wires[i].line = e.line }
                wires[i].declared = wires[i].declared || e.kind == .link
            } else {
                pairs[key] = wires.count
                wires.append(Wire(a: key[0], b: key[1], line: e.line, declared: e.kind == .link))
            }
        }
        var near = Array(repeating: [Int](), count: cards.count)
        for w in wires {
            near[w.a].append(w.b)
            near[w.b].append(w.a)
        }

        // Places west to east along the shortest arc holding them, split
        // at the widest gaps of longitude into as many columns as fit.
        let places = cards.indices.filter { !cards[$0].isPill }
        let pills = cards.indices.filter { cards[$0].isPill }
            .sorted { (near[$0].count, cards[$0].width) > (near[$1].count, cards[$1].width) }
        let (centre, arc) = GeoView.lonBounds(places.map { cards[$0].lon })
        let key = { (k: Int) -> Double in (cards[k].lon - (centre - arc / 2) + 720 + 1e-6).truncatingRemainder(dividingBy: 360) }
        let order = places.sorted { key($0) < key($1) }
        let gaps = order.count > 1
            ? (0..<(order.count - 1)).sorted { key(order[$0 + 1]) - key(order[$0]) > key(order[$1 + 1]) - key(order[$1]) } : []
        let gap = 2

        /// Columns for `nc` columns of places, with the pills where they
        /// fit; nil when they don't, unless `dropping`, when a pill without
        /// room is left out.
        func attempt(_ nc: Int, dropping: Bool) -> (col: [Int: Int], left: [Int])? {
            let cuts = Set(gaps.prefix(max(0, nc - 1)).map { $0 + 1 })
            var col: [Int: Int] = [:]
            var c = 0
            for (i, k) in order.enumerated() {
                if cuts.contains(i) { c += 1 }
                col[k] = c
            }
            let n = max(1, c + 1)
            var w = Array(repeating: 0, count: n), count = Array(repeating: 0, count: n)
            for k in places {
                w[col[k]!] = max(w[col[k]!], cards[k].width)
                count[col[k]!] += 1
            }
            let room = cols - gap * (n - 1)
            guard w.reduce(0, +) <= room, count.allSatisfy({ $0 <= rows }) || dropping else { return nil }
            var left: [Int] = []
            for p in pills {
                let options = (0..<n).filter { count[$0] < rows && w.reduce(0, +) - w[$0] + max(w[$0], cards[p].width) <= room }
                let linked = { (c: Int) in near[p].filter { col[$0] == c }.count }
                guard let best = options.min(by: { a, b in
                    let ca = (max(w[a], cards[p].width) - w[a]) * 10 - linked(a) * 3 + count[a]
                    let cb = (max(w[b], cards[p].width) - w[b]) * 10 - linked(b) * 3 + count[b]
                    return ca < cb
                }) else {
                    if dropping { left.append(p); continue }
                    return nil
                }
                col[p] = best
                w[best] = max(w[best], cards[p].width)
                count[best] += 1
            }
            return (col, left)
        }
        // A column per region: places less than 12° apart share one while
        // there's room for it, as a city's servers and its suburbs' do.
        let regions = 1 + (0..<max(0, order.count - 1)).filter { key(order[$0 + 1]) - key(order[$0]) >= 12 }.count
        let most = min(order.count, max(1, cols / 9))
        var chosen: (col: [Int: Int], left: [Int])?
        for nc in stride(from: min(regions, most), through: 1, by: -1) where chosen == nil { chosen = attempt(nc, dropping: false) }
        for nc in stride(from: most, through: regions + 1, by: -1) where chosen == nil { chosen = attempt(nc, dropping: false) }
        for nc in stride(from: most, through: 1, by: -1) where chosen == nil { chosen = attempt(nc, dropping: true) }
        guard let (col, left) = chosen else { return }
        leftOut = left.flatMap { cards[$0].nodes }

        // Down each column: places north to south, then pills, each by
        // the places it links to.
        var shown = cards.indices.filter { col[$0] != nil }
        let n = (shown.map { col[$0]! }.max() ?? 0) + 1
        var lists = (0..<n).map { c in shown.filter { col[$0] == c } }
        func north(_ k: Int) -> Double {
            if !cards[k].isPill { return cards[k].lat }
            let lats = near[k].filter { !cards[$0].isPill }.map { cards[$0].lat }
            return lats.isEmpty ? -1000 : lats.reduce(0, +) / Double(lats.count) - 500
        }
        for c in lists.indices { lists[c].sort { north($0) > north($1) } }
        // Past what a column holds, the rest are counted.
        for c in lists.indices where lists[c].count > rows {
            let cut = lists[c].suffix(lists[c].count - rows + 1)
            leftOut += cut.flatMap { cards[$0].nodes }
            lists[c].removeLast(cut.count)
        }
        if !leftOut.isEmpty, let last = lists.indices.last {
            cards.append(Card(title: "+\(leftOut.count)", nodes: leftOut, isPill: true, isMore: true))
            cards[cards.count - 1].width = CellText.width("+\(leftOut.count)") + 2
            lists[last].append(cards.count - 1)
            if lists[last].count > rows, let drop = lists[last].dropLast().last {
                lists[last].removeAll { $0 == drop }
            }
        }
        shown = lists.flatMap { $0 }

        // Each place on the line its latitude puts it, as a map would,
        // pressed apart down its column: a blank line between cards where
        // the column has room, and the pills beneath the places.
        let lats = places.map { cards[$0].lat }
        let top = lats.max() ?? 0, bottom = lats.min() ?? 0
        var rowOf: [Int: Int] = [:]
        for c in lists.indices {
            let list = lists[c]
            let gap = 2 * list.count - 1 <= rows ? 2 : 1
            var want = list.map { k -> Int in
                guard !cards[k].isPill, top > bottom else { return rows / 2 }
                return Int(((top - cards[k].lat) / (top - bottom) * Double(rows - 1)).rounded())
            }
            for i in want.indices.dropFirst() { want[i] = max(want[i], want[i - 1] + gap) }
            if let last = want.last, last > rows - 1 {
                want[want.count - 1] = rows - 1
                for i in want.indices.reversed().dropFirst() { want[i] = min(want[i], want[i + 1] - gap) }
            }
            for (k, r) in zip(list, want) { rowOf[k] = max(0, r) }
        }
        let widths = lists.map { list in list.map { cards[$0].width }.max() ?? 0 }
        let spare = max(0, cols - widths.reduce(0, +))
        let margin = n > 1 ? min(2, spare / (n + 1)) : (cols - widths[0]) / 2
        let between = n > 1 ? (spare - 2 * margin) / (n - 1) : 0
        var x = margin
        for c in lists.indices {
            for k in lists[c] {
                cards[k].col = c
                cards[k].row = rowOf[k] ?? 0
                cards[k].x = x + (widths[c] - cards[k].width) / 2
            }
            x += widths[c] + between
        }
        let kept = Set(shown)
        self.cards = cards
        self.wires = wires.filter { kept.contains($0.a) && kept.contains($0.b) }
        // Only cards laid out are drawn.
        for k in cards.indices where !kept.contains(k) { self.cards[k].width = 0 }
    }

    /// A chip's cells: its name, a space, a mark per node, the rest
    /// counted; a pill's, its mark, a space and its name. A cell's padding
    /// each side.
    static func width(_ c: Card) -> Int {
        if c.isPill {
            let more = c.nodes.count > 1 ? CellText.width(" +\(c.nodes.count - 1)") : 0
            return 2 + CellText.width(c.title) + more + 2
        }
        let m = c.marks
        return CellText.width(c.title) + 1 + m.shown.count + (m.more > 0 ? CellText.width("+\(m.more)") : 0) + 2
    }
}
