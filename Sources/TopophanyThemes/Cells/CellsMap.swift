import Foundation
import TopophanySections

/// The Terminal look's map, as the TUI draws it: the land shaded cell by
/// cell under a lattice of braille dots with a dotted coast, each place a
/// mark of `topo`'s and its name, arcs between places in dots; or, in the
/// virtual view, places as small boxes wired in dots.
struct CellsMap {
    var map: MapSection
    var p: CellsPalette
    var metrics: CellMetrics
    var detail = MapDetail.places
    /// In one tone, as the desktop draws a widget while another app is in
    /// front.
    var plain = false

    /// A braille dot's width and height, in points.
    var dotW: Double { metrics.cell / 2 }
    var dotH: Double { metrics.line / 4 }

    /// The map in `cols` × `rows` cells with its top left at (x, y), moved
    /// by `transform`, in dots.
    func items(x: Double, y: Double, cols: Int, rows: Int, transform: MapTransform = .identity) -> [CellItem] {
        guard cols > 4, rows > 1 else { return [] }
        switch map.mode {
        case .geo: return geo(x: x, y: y, cols: cols, rows: rows, transform: transform)
        case .virtual: return virtual(x: x, y: y, cols: cols, rows: rows, transform: transform)
        }
    }

    // MARK: colors

    /// The TUI's land: its ink toward its accent, as its land, lattice and
    /// coast tones are.
    var landFill: RGBA { p.ink.mix(p.accent, 0.09) }
    var land: RGBA { plain ? p.text.opacity(0.22) : p.ink.mix(p.accent, 0.24) }
    var coast: RGBA { plain ? p.text.opacity(0.38) : p.ink.mix(p.accent, 0.42) }

    func tone(_ m: Mark) -> RGBA { plain ? (m == .up ? p.text.opacity(0.5) : p.text) : p.tone(m) }

    /// A line's color, how it's broken (dots on, dots off) and its priority,
    /// as the TUI's edgeStyle gives them.
    func lineStyle(_ line: MapSection.Line, declared: Bool) -> (RGBA, Int, Int) {
        var c: RGBA
        var pri: Int
        switch line {
        case .up, .carried: (c, pri) = (p.up.mix(p.ink, 0.5), 4)
        case .affected, .degraded: (c, pri) = (p.warn, 5)
        case .down: (c, pri) = (p.down, 6)
        case .unknown, .withheld: (c, pri) = (p.unknown.mix(p.ink, 0.5), 3)
        }
        var dash = 0
        if !declared {
            dash = 2
            if line == .unknown || line == .carried || line == .withheld {
                c = c.mix(p.ink, 0.3)
                pri -= 1
            }
        }
        if plain { c = line.rank >= MapSection.Line.affected.rank ? p.text : p.text.opacity(0.35) }
        return (c, pri, dash)
    }

    // MARK: dots

    /// A braille raster: each cell shows only its highest-priority dots, so
    /// a route crossing land stays a clean line.
    struct Dots {
        var cols: Int, rows: Int
        var bits: [UInt8]
        var color: [RGBA]
        var pri: [Int]

        init(cols: Int, rows: Int) {
            self.cols = cols
            self.rows = rows
            bits = Array(repeating: 0, count: cols * rows)
            color = Array(repeating: RGBA(0, 0, 0, 0), count: cols * rows)
            pri = Array(repeating: 0, count: cols * rows)
        }

        mutating func set(_ px: Int, _ py: Int, _ c: RGBA, _ p: Int) {
            guard px >= 0, py >= 0, px < cols * 2, py < rows * 4 else { return }
            let i = (py / 4) * cols + px / 2
            let bit = UInt8(1) << UInt8((py % 4) * 2 + px % 2)
            if bits[i] == 0 || p > pri[i] {
                (bits[i], color[i], pri[i]) = (bit, c, p)
            } else if p == pri[i] {
                bits[i] |= bit
                color[i] = c
            }
        }

        mutating func clear(cell cx: Int, _ cy: Int) {
            guard cx >= 0, cy >= 0, cx < cols, cy < rows else { return }
            bits[cy * cols + cx] = 0
        }

        /// The dots as points, one item per color.
        func items(x: Double, y: Double, dotW: Double, dotH: Double, diameter: Double) -> [CellItem] {
            var byColor: [RGBA: [CGPoint]] = [:]
            for cy in 0..<rows {
                for cx in 0..<cols {
                    let b = bits[cy * cols + cx]
                    guard b != 0 else { continue }
                    for row in 0..<4 {
                        for col in 0..<2 where b & (UInt8(1) << UInt8(row * 2 + col)) != 0 {
                            byColor[color[cy * cols + cx], default: []].append(
                                CGPoint(x: x + (Double(cx * 2 + col) + 0.5) * dotW, y: y + (Double(cy * 4 + row) + 0.5) * dotH))
                        }
                    }
                }
            }
            return byColor.sorted { $0.key.a < $1.key.a }.map { .points($0.value, $0.key, diameter: diameter) }
        }
    }

    // MARK: geo

    func geo(x x0: Double, y y0: Double, cols: Int, rows: Int, transform: MapTransform) -> [CellItem] {
        let W = cols * 2, H = rows * 4
        let ky = dotH / dotW
        let scene = GeoScene(map, size: CGSize(width: W, height: H), ky: ky, transform: transform, samePlace: 24,
                             collide: CGSize(width: 5, height: 4))
        var items: [CellItem] = []
        var d = Dots(cols: cols, rows: rows)

        // The land, shaded cell by cell, then its lattice and coast.
        var grid = Array(repeating: false, count: W * H)
        for py in 0..<H {
            for px in 0..<W where scene.isLand(CGPoint(x: Double(px) + 0.5, y: Double(py) + 0.5)) { grid[py * W + px] = true }
        }
        func isLand(_ px: Int, _ py: Int) -> Bool {
            if px >= 0, py >= 0, px < W, py < H { return grid[py * W + px] }
            return scene.isLand(CGPoint(x: Double(px) + 0.5, y: Double(py) + 0.5))
        }
        if !plain {
            for cy in 0..<rows {
                for cx in 0..<cols {
                    var n = 0
                    for k in 0..<8 where grid[(cy * 4 + k / 2) * W + cx * 2 + k % 2] { n += 1 }
                    guard n > 0 else { continue }
                    items.append(.fill(CGRect(x: x0 + Double(cx) * metrics.cell, y: y0 + Double(cy) * metrics.line,
                                              width: metrics.cell + 0.3, height: metrics.line + 0.3),
                                       p.ink.mix(landFill, Double(n) / 8), radius: 0))
                }
            }
        }
        // The lattice keeps to the map, so it moves with it.
        let ox = Int(transform.offset.x.rounded()), oy = Int(transform.offset.y.rounded())
        for py in 0..<H {
            for px in 0..<W where grid[py * W + px] {
                if !isLand(px - 1, py) || !isLand(px + 1, py) || !isLand(px, py - 1) || !isLand(px, py + 1) {
                    d.set(px, py, coast, 1)
                } else if (px - ox) % 2 == 0 && (py - oy) % 2 == 0 {
                    d.set(px, py, land, 1)
                }
            }
        }

        // A fold's seam: a dotted line down a blank strip, headed by the
        // degrees it holds.
        var taken = Array(repeating: false, count: cols * rows)
        func take(_ cx: Int, _ cy: Int, _ w: Int) {
            for i in max(0, cx)..<min(cols, cx + w) where cy >= 0 && cy < rows { taken[cy * cols + i] = true }
        }
        var texts: [(x: Int, y: Int, String, RGBA, Bool)] = []
        let tag = transform.zoom > 1.001 ? " \(MapCanvas.zoomText(transform.zoom)) " : " " + frameWord + " "
        take(cols - CellText.width(tag) - 1, 0, CellText.width(tag) + 1)
        for seam in scene.seams where seam.x > 0 && seam.x < Double(W) {
            let sx = Int(seam.x)
            for py in stride(from: 0, to: H, by: 2) { d.set(sx, py, p.line.mix(p.accent, 0.2), 1) }
            let label = " " + tr("\(seam.degrees)° folded") + " "
            let lx = sx / 2 - CellText.width(label) / 2
            if lx >= 0, lx + CellText.width(label) < cols - CellText.width(tag) - 1 {
                texts.append((lx, 0, label, p.line.mix(p.accent, 0.45), false))
                take(lx, 0, CellText.width(label))
            }
        }

        // Arcs, bowed north, stopping short of the marks they join.
        for arc in scene.arcs {
            let (c, pri, dash) = lineStyle(arc.line, declared: arc.declared)
            let length = hypot(arc.end.x - arc.start.x, arc.end.y - arc.start.y) + hypot(arc.control.x - arc.start.x, arc.control.y - arc.start.y)
            let n = max(2, Int(length * 1.2))
            var i = 0
            for k in 0...n {
                let pt = arc.point(at: Double(k) / Double(n))
                // Outside the cells the marks stand in.
                guard abs(pt.x - arc.start.x) > 2.5 || abs(pt.y - arc.start.y) > 3,
                      abs(pt.x - arc.end.x) > 2.5 || abs(pt.y - arc.end.y) > 3 else { continue }
                if dash == 0 || (i / dash) % 2 == 0 { d.set(Int(pt.x.rounded()), Int(pt.y.rounded()), c, pri) }
                i += 1
            }
        }

        // A quiet ring about each place, a second for trouble.
        for s in scene.sites {
            let c = tone(s.mark)
            let trouble = s.mark == .down || s.mark == .degraded
            ring(&d, s.point, 3.2, ky, plain ? c.opacity(0.5) : c.mix(p.ink, 0.55), 7)
            if trouble { ring(&d, s.point, 6.2, ky, plain ? c.opacity(0.35) : c.mix(p.ink, 0.72), 6) }
        }

        // Names beside their marks, trouble first, where they cover no other
        // name, mark or seam.
        let siteCells = scene.sites.map { (Int($0.point.x) / 2, Int($0.point.y) / 4) }
        for (cx, cy) in siteCells where cx >= 0 && cy >= 0 && cx < cols && cy < rows { take(cx, cy, 1) }
        let order = scene.sites.indices.sorted { a, b in
            let ta = scene.sites[a].mark == .down || scene.sites[a].mark == .degraded
            let tb = scene.sites[b].mark == .down || scene.sites[b].mark == .degraded
            return ta != tb ? ta : scene.sites[a].point.y < scene.sites[b].point.y
        }
        for i in order {
            let s = scene.sites[i]
            let (cx, cy) = siteCells[i]
            guard cx >= 0, cy >= 0, cx < cols, cy < rows, !s.title.isEmpty else { continue }
            let trouble = s.mark == .down || s.mark == .degraded
            guard detail != .marks || trouble else { continue }
            let label = CellText.truncate(s.title, max(4, cols / 2))
            let w = CellText.width(label)
            let candidates = [(cx + 2, cy), (cx - 1 - w, cy), (cx - w / 2, cy - 1), (cx - w / 2, cy + 1)]
            guard let (lx, ly) = candidates.first(where: { lx, ly in
                lx >= 0 && ly >= 0 && lx + w <= cols && ly < rows && !(lx..<(lx + w)).contains { taken[ly * cols + $0] }
            }) else { continue }
            take(lx - 1, ly, w + 2)
            texts.append((lx, ly, label, trouble ? (plain ? p.text : p.text) : p.muted, trouble))
        }
        for t in texts { for k in 0..<CellText.width(t.2) { d.clear(cell: t.x + k, t.y) } }
        for (cx, cy) in siteCells { d.clear(cell: cx, cy) }

        items += d.items(x: x0, y: y0, dotW: dotW, dotH: dotH, diameter: min(dotW, dotH) * 0.6)
        for (i, s) in scene.sites.enumerated() {
            let (cx, cy) = siteCells[i]
            guard cx >= 0, cy >= 0, cx < cols, cy < rows else { continue }
            let gx = x0 + Double(cx) * metrics.cell, gy = y0 + Double(cy) * metrics.line
            if s.coloOnly {
                items.append(.glyph(x: gx, y: gy, .mark(.offline), s.mark == .up ? p.up.mix(p.ink, 0.45) : p.unknown))
            } else {
                items.append(.glyph(x: gx, y: gy, .mark(s.mark), tone(s.mark)))
            }
        }
        // Trouble moved out of view, at the edge toward it.
        for (i, pin) in scene.offView(inset: 1) {
            let cx = min(cols - 1, max(0, Int(pin.x) / 2)), cy = min(rows - 1, max(0, Int(pin.y) / 4))
            items.append(.glyph(x: x0 + Double(cx) * metrics.cell, y: y0 + Double(cy) * metrics.line,
                                .mark(scene.sites[i].mark), tone(scene.sites[i].mark)))
        }
        for t in texts {
            items.append(.text(x: x0 + Double(t.x) * metrics.cell, y: y0 + Double(t.y) * metrics.line, t.2, t.3, bold: t.4))
        }
        items.append(.text(x: x0 + Double(cols - CellText.width(tag) - 1) * metrics.cell, y: y0, tag, p.faint, bold: false))
        return items
    }

    var frameWord: String { map.frame == .world ? tr("world") : tr("fit") }

    /// Dots `r` dot widths about `c`, round on screen when dots are `ky`
    /// times as tall as they are wide.
    func ring(_ d: inout Dots, _ c: CGPoint, _ r: Double, _ ky: Double, _ color: RGBA, _ pri: Int) {
        let steps = max(12, Int(r * 7))
        for i in 0..<steps {
            let a = 2 * Double.pi * Double(i) / Double(steps)
            d.set(Int((c.x + cos(a) * r).rounded()), Int((c.y + sin(a) * r / ky).rounded()), color, pri)
        }
    }

    // MARK: virtual

    /// The virtual geo map: each place a chip of its name and its nodes'
    /// marks, in columns west to east, what has no place a pill beside
    /// what it links to, wired in dots as the geo map's arcs are.
    /// Magnified, the cards move apart; their words keep their size.
    func virtual(x x0: Double, y y0: Double, cols: Int, rows: Int, transform: MapTransform) -> [CellItem] {
        let c = metrics.cell, l = metrics.line
        let layout = CellsVirtual(map, cols: cols, rows: rows)
        let bounds = CGRect(x: x0, y: y0, width: Double(cols) * c, height: Double(rows) * l)
        // Where a point of the laid-out map shows, magnified and moved.
        func at(_ pt: CGPoint) -> CGPoint {
            CGPoint(x: x0 + pt.x * transform.zoom + transform.offset.x * dotW, y: y0 + pt.y * transform.zoom + transform.offset.y * dotH)
        }
        // Each card's line: its left, middle and right, before magnifying.
        func rect(_ k: Int) -> CGRect {
            let card = layout.cards[k]
            let mid = at(CGPoint(x: (Double(card.x) + Double(card.width) / 2) * c, y: (Double(card.row) + 0.5) * l))
            return CGRect(x: (mid.x - Double(card.width) * c / 2).rounded(), y: mid.y - l / 2, width: Double(card.width) * c, height: l)
        }
        let rects = layout.cards.indices.map(rect)
        // Magnified, how far, at the top right, the wires kept clear of it.
        let tag = transform.zoom > 1.001 ? " \(MapCanvas.zoomText(transform.zoom)) " : ""
        let tagRect = CGRect(x: x0 + Double(cols - CellText.width(tag) - 1) * c, y: y0, width: Double(CellText.width(tag)) * c, height: l)
        var items: [CellItem] = []

        // Wires, in dots, leaving each card on the side toward the other
        // and spread along its edge by where they go; a pair in one column
        // loops out and back on the side with more room.
        let lastCol = layout.cards.map(\.col).max() ?? 0
        struct End: Hashable { var card: Int; var side: Double }
        var ends: [End: [(wire: Int, toward: Double)]] = [:]
        var sides: [(Double, Double)] = []
        for (i, w) in layout.wires.enumerated() {
            let a = layout.cards[w.a], b = layout.cards[w.b]
            let side: (Double, Double) = a.col == b.col ? (a.col == lastCol && lastCol > 0 ? (-1, -1) : (1, 1))
                : a.col < b.col ? (1, -1) : (-1, 1)
            sides.append(side)
            ends[End(card: w.a, side: side.0), default: []].append((i, rects[w.b].midY))
            ends[End(card: w.b, side: side.1), default: []].append((i, rects[w.a].midY))
        }
        var endY: [String: Double] = [:]
        for (end, list) in ends {
            let r = rects[end.card]
            let span = min(r.height - 6, Double(list.count - 1) * dotH * 0.9)
            for (j, e) in list.sorted(by: { $0.toward < $1.toward }).enumerated() {
                endY["\(e.wire)-\(end.card)"] = r.midY - span / 2 + (list.count > 1 ? span * Double(j) / Double(list.count - 1) : 0)
            }
        }
        var dots: [RGBA: [CGPoint]] = [:]
        for i in layout.wires.indices.sorted(by: { layout.wires[$0].line.rank < layout.wires[$1].line.rank }) {
            let w = layout.wires[i], (sa, sb) = sides[i]
            let ra = rects[w.a], rb = rects[w.b]
            guard layout.cards[w.a].width > 0, layout.cards[w.b].width > 0 else { continue }
            let a = CGPoint(x: sa > 0 ? ra.maxX + 1 : ra.minX - 1, y: endY["\(i)-\(w.a)"] ?? ra.midY)
            let b = CGPoint(x: sb > 0 ? rb.maxX + 1 : rb.minX - 1, y: endY["\(i)-\(w.b)"] ?? rb.midY)
            let reach = max(2 * c, abs(b.x - a.x) * 0.45)
            let p1 = CGPoint(x: a.x + sa * reach, y: a.y), p2 = CGPoint(x: b.x + sb * reach, y: b.y)
            let (color, _, dash) = lineStyle(w.line, declared: w.declared)
            let length = hypot(b.x - a.x, b.y - a.y) + 2 * reach
            let n = max(2, Int(length / dotW))
            for j in 0...n where dash == 0 || (j / dash) % 2 == 0 {
                let t = Double(j) / Double(n), u = 1 - t
                let pt = CGPoint(x: u * u * u * a.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * b.x,
                                 y: u * u * u * a.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * b.y)
                guard bounds.contains(pt), !rects.contains(where: { $0.insetBy(dx: -0.5, dy: 1).contains(pt) }),
                      tag.isEmpty || !tagRect.contains(pt) else { continue }
                dots[color, default: []].append(pt)
            }
        }
        let d = min(dotW, dotH) * 0.6
        items += dots.map { .points($0.value, $0.key, diameter: d) }

        // Cards: a chip for a place, a pill for the rest, whole or not at
        // all where magnified past the map's edge.
        for (k, card) in layout.cards.enumerated() where card.width > 0 {
            let r = rects[k]
            guard bounds.insetBy(dx: -1, dy: -1).contains(r) else { continue }
            let trouble = card.mark == .down || card.mark == .degraded
            let y = r.minY
            var x = r.minX + c
            if card.isMore {
                items.append(.text(x: x, y: y, card.title, p.faint, bold: false))
                continue
            }
            items.append(.fill(r.insetBy(dx: 0, dy: 1), card.isPill ? p.pillBackground(card.mark) : p.key, radius: 4))
            if card.isPill {
                items.append(.glyph(x: x, y: y, .mark(card.mark), tone(card.mark)))
                items.append(.text(x: x + 2 * c, y: y, card.title, p.text, bold: false))
                if card.nodes.count > 1 {
                    items.append(.text(x: x + Double(2 + CellText.width(card.title)) * c, y: y, " +\(card.nodes.count - 1)", p.faint, bold: false))
                }
                continue
            }
            items.append(.text(x: x, y: y, card.title, trouble ? p.text : p.muted, bold: trouble))
            x += Double(CellText.width(card.title) + 1) * c
            let m = card.marks
            for n in m.shown {
                items.append(.glyph(x: x, y: y, .mark(n.mark), tone(n.mark)))
                x += c
            }
            if m.more > 0 { items.append(.text(x: x, y: y, "+\(m.more)", p.faint, bold: false)) }
        }
        if !tag.isEmpty { items.append(.text(x: tagRect.minX, y: y0, tag, p.faint, bold: false)) }
        return items
    }
}
