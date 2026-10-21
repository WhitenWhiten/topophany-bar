import SwiftUI
import TopophanySections

/// How much a map says beside each place.
enum MapDetail: Sendable, Hashable {
    /// Marks, and the names of places that need a look.
    case marks
    /// Every place's name: the panel's map.
    case places
    /// Every place's name and its nodes beneath it, where there's room.
    case nodes
}

/// The cards renderer's map: the land as a matrix of fine dots, dithered
/// where it meets the sea, as `topo`'s geo map and the disk image draw it;
/// each place a mark of `topo`'s and its name; the lines between places
/// as arcs, quiet while they hold and in their color when they don't.
struct CardsMapPainter {
    var map: MapSection
    var p: CardsPalette
    var t: CardsType
    var detail = MapDetail.places
    /// In one tone, as the desktop draws a widget while another app is in
    /// front: weight tells trouble from the rest.
    var vibrant = false

    /// Between the land's dots, and each dot's width.
    var pitch = 2.6
    var dot = 1.3
    /// A mark's width.
    var markSize = 9.5

    // MARK: colors

    /// The land's ink: the text's on glass, the accent at night, the page's
    /// ink on matte.
    var landInk: Color {
        if vibrant { return p.l1 }
        return switch p.style.surface {
        case .glass: p.isDark ? .white : .black
        case .night: p.accent
        case .matte: p.l1
        }
    }

    var landStrength: Double {
        let base: Double = switch p.style.surface {
        case .glass: p.isDark ? 0.34 : 0.24
        case .night: p.isDark ? 0.42 : 0.4
        case .matte: p.isDark ? 0.3 : 0.24
        }
        return base * (p.increaseContrast ? 1.5 : 1)
    }

    func markColor(_ m: Mark) -> Color {
        if vibrant { return m == .up ? p.l1.opacity(0.45) : p.l1 }
        return p.listColor(m)
    }

    func lineStyle(_ line: MapSection.Line, declared: Bool) -> (color: Color, width: Double, dash: [CGFloat]) {
        let implied: [CGFloat] = declared ? [] : [3, 2.6]
        if vibrant {
            switch line {
            case .down, .degraded, .affected: return (p.l1, 1.4, implied)
            case .up: return (p.l1.opacity(0.35), 1, implied)
            case .carried: return (p.l1.opacity(0.25), 0.9, implied)
            case .unknown, .withheld: return (p.l1.opacity(0.3), 0.85, [1.6, 2.4])
            }
        }
        return switch line {
        case .up: (p.up.opacity(p.isDark ? 0.5 : 0.6), 1, implied)
        case .carried: (p.up.opacity(p.isDark ? 0.3 : 0.38), 0.9, implied)
        case .affected: (p.warn.opacity(0.8), 1.2, implied)
        case .degraded: (p.warn, 1.3, implied)
        case .down: (p.down, 1.5, implied)
        case .unknown: (p.unknown.opacity(0.6), 0.85, [1.6, 2.4])
        case .withheld: (p.unknown.opacity(0.45), 0.85, [1.6, 2.4])
        }
    }

    // MARK: drawing

    func draw(_ ctx: GraphicsContext, size: CGSize, transform: MapTransform) {
        drawGeo(ctx, size: size, transform: transform)
    }

    func drawGeo(_ ctx: GraphicsContext, size: CGSize, transform: MapTransform) {
        let scene = GeoScene(map, size: size, transform: transform)
        let bounds = CGRect(origin: .zero, size: size)
        let r = markSize / 2

        // Labels first: the land keeps clear of them.
        let labels = labels(ctx, scene: scene, bounds: bounds.insetBy(dx: 3, dy: 2), radius: r)
        let clear = labels.values.map { $0.rect.insetBy(dx: -2, dy: -1) }

        drawLand(ctx, scene: scene, size: size, clear: clear)
        drawSeams(ctx, scene: scene, size: size)

        // Arcs, the calm under the troubled.
        for arc in scene.arcs.sorted(by: { $0.line.rank < $1.line.rank }) {
            let s = lineStyle(arc.line, declared: arc.declared)
            ctx.stroke(trimmed(arc, by: r + 2.5), with: .color(s.color),
                       style: StrokeStyle(lineWidth: s.width, lineCap: .round, dash: s.dash))
        }

        // Each place: a quiet ring, a second one for trouble, and its mark.
        for s in scene.sites where bounds.insetBy(dx: -r, dy: -r).contains(s.point) {
            drawSite(ctx, s)
        }
        for (i, pin) in scene.offView(inset: r + 2) {
            drawPin(ctx, scene.sites[i], at: pin)
        }
        for (_, l) in labels { l.draw(ctx) }
    }

    /// The land's dots: one wherever a dither threshold says enough of its
    /// cell is land, so a coast frays into the sea instead of stepping.
    /// Near the network's places the land comes up a little, as the disk
    /// image's does near its arc; toward the map's edges it fades.
    func drawLand(_ ctx: GraphicsContext, scene: GeoScene, size: CGSize, clear: [CGRect]) {
        let o = scene.transform.offset
        let x0 = o.x.truncatingRemainder(dividingBy: pitch) - pitch, y0 = o.y.truncatingRemainder(dividingBy: pitch) - pitch
        let sites = scene.sites.map(\.point)
        let levels = 8
        var paths = Array(repeating: Path(), count: levels)
        let strength = landStrength
        let near = markSize / 2 + 2.5
        var y = y0
        while y < size.height + pitch {
            var x = x0
            let j = Int(((y - o.y) / pitch).rounded(.down))
            while x < size.width + pitch {
                defer { x += pitch }
                let c = CGPoint(x: x + pitch / 2, y: y + pitch / 2)
                guard c.x > 0, c.y > 0, c.x < size.width, c.y < size.height else { continue }
                let cover = scene.land(around: c, width: pitch, height: pitch, samples: 3)
                guard cover > 0 else { continue }
                let i = Int(((x - o.x) / pitch).rounded(.down))
                guard cover >= Self.bayer(i, j) else { continue }
                var nearest = Double.infinity
                for s in sites {
                    let d = hypot(s.x - c.x, s.y - c.y)
                    nearest = min(nearest, d)
                }
                guard nearest > near, !clear.contains(where: { $0.contains(c) }) else { continue }
                let edge = min(c.x, size.width - c.x, c.y, size.height - c.y)
                let fade = Self.smoothstep(0, 14, edge)
                let glow = exp(-nearest / 56)
                let a = fade * (0.42 + 0.58 * glow)
                let level = min(levels - 1, Int(a * Double(levels)))
                guard level > 0 else { continue }
                let d = dot * (0.8 + 0.2 * cover + 0.25 * glow)
                paths[level].addEllipse(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
            }
            y += pitch
        }
        for (k, path) in paths.enumerated() where !path.isEmpty {
            let a = strength * (Double(k) + 0.5) / Double(levels) * 1.5
            ctx.fill(path, with: .color(landInk.opacity(min(1, a))))
        }
    }

    /// A fold's seam: a dotted rule down the blank strip, headed by the
    /// degrees of longitude it holds, so it's never taken for a coast.
    func drawSeams(_ ctx: GraphicsContext, scene: GeoScene, size: CGSize) {
        for seam in scene.seams where seam.x > 0 && seam.x < size.width {
            var dots = Path()
            var y = 18.0
            while y < size.height - 4 {
                dots.addEllipse(in: CGRect(x: seam.x - 0.5, y: y, width: 1, height: 1))
                y += 3
            }
            ctx.fill(dots, with: .color(p.l3.opacity(0.6)))
            let label = ctx.resolve(Text(verbatim: "\(seam.degrees)°").font(t.font(8.5, .medium)).foregroundStyle(p.l3))
            let w = label.measure(in: CGSize(width: 100, height: 20))
            // Whole, or not at all: a magnified map can carry it to an edge.
            guard seam.x - w.width / 2 >= 2, seam.x + w.width / 2 <= size.width - 2 else { continue }
            ctx.draw(label, in: CGRect(x: seam.x - w.width / 2, y: 3, width: w.width, height: w.height))
        }
    }

    func drawSite(_ ctx: GraphicsContext, _ s: GeoScene.Site) {
        let c = s.point, r = markSize / 2
        let color = markColor(s.mark)
        if s.coloOnly {
            let ring = Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
            ctx.stroke(ring, with: .color(s.mark == .up ? color : p.unknown), lineWidth: 1)
            return
        }
        let trouble = s.mark == .down || s.mark == .degraded
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: 2 * r + 6, height: 2 * r + 6)),
                   with: .color(color.opacity(trouble ? 0.5 : 0.3)), lineWidth: 0.75)
        if trouble {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 7, y: c.y - r - 7, width: 2 * r + 14, height: 2 * r + 14)),
                       with: .color(color.opacity(0.18)), lineWidth: 0.75)
        }
        var m = ctx
        m.translateBy(x: c.x - r, y: c.y - r)
        CardMark.draw(s.mark, in: m, size: markSize, color: color, on: p.on)
    }

    /// Trouble moved out of view: its mark at the edge, and a fine chevron
    /// toward where it is.
    func drawPin(_ ctx: GraphicsContext, _ s: GeoScene.Site, at pin: CGPoint) {
        let color = markColor(s.mark)
        let a = atan2(s.point.y - pin.y, s.point.x - pin.x)
        var chevron = Path()
        let tip = CGPoint(x: pin.x + cos(a) * 9, y: pin.y + sin(a) * 9)
        chevron.move(to: CGPoint(x: tip.x - cos(a - 0.6) * 3.5, y: tip.y - sin(a - 0.6) * 3.5))
        chevron.addLine(to: tip)
        chevron.addLine(to: CGPoint(x: tip.x - cos(a + 0.6) * 3.5, y: tip.y - sin(a + 0.6) * 3.5))
        ctx.stroke(chevron, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        var m = ctx
        let k = markSize * 0.8
        m.translateBy(x: pin.x - k / 2, y: pin.y - k / 2)
        CardMark.draw(s.mark, in: m, size: k, color: color, on: p.on)
    }

    /// An arc from just outside one mark to just outside the other.
    func trimmed(_ arc: GeoScene.Arc, by r: Double) -> Path {
        let n = 48
        let pts = (0...n).map { arc.point(at: Double($0) / Double(n)) }
        let kept = pts.filter { hypot($0.x - arc.start.x, $0.y - arc.start.y) >= r && hypot($0.x - arc.end.x, $0.y - arc.end.y) >= r }
        var path = Path()
        if kept.count > 1 { path.addLines(kept) }
        return path
    }

    // MARK: labels

    struct Label {
        var rect: CGRect
        var title: GraphicsContext.ResolvedText
        var titleSize: CGSize
        var rows: [(mark: Mark, color: Color, text: GraphicsContext.ResolvedText)]
        var rowHeight: Double
        var markSize: Double
        var leftAligned: Bool
        var on: Color

        func draw(_ ctx: GraphicsContext) {
            ctx.draw(title, in: CGRect(x: leftAligned ? rect.minX : rect.maxX - titleSize.width, y: rect.minY,
                                       width: titleSize.width, height: titleSize.height))
            for (k, row) in rows.enumerated() {
                let y = rect.minY + titleSize.height + Double(k) * rowHeight
                let size = row.text.measure(in: CGSize(width: rect.width, height: rowHeight))
                let x = leftAligned ? rect.minX : rect.maxX - size.width - markSize - 3
                var m = ctx
                m.translateBy(x: x, y: y + (rowHeight - markSize) / 2)
                CardMark.draw(row.mark, in: m, size: markSize, color: row.color, on: on)
                ctx.draw(row.text, in: CGRect(x: x + markSize + 3, y: y, width: size.width, height: rowHeight))
            }
        }
    }

    func labels(_ ctx: GraphicsContext, scene: GeoScene, bounds: CGRect, radius r: Double) -> [Int: Label] {
        let first = labels(ctx, scene: scene, bounds: bounds, radius: r, nodes: detail == .nodes, keepOut: [], only: nil)
        guard detail == .nodes else { return first }
        // A place whose nodes don't fit beside it keeps its name alone.
        let missing = Set(scene.sites.indices).subtracting(first.keys)
        guard !missing.isEmpty else { return first }
        let second = labels(ctx, scene: scene, bounds: bounds, radius: r, nodes: false, keepOut: first.values.map(\.rect), only: missing)
        return first.merging(second) { a, _ in a }
    }

    func labels(_ ctx: GraphicsContext, scene: GeoScene, bounds: CGRect, radius r: Double, nodes: Bool, keepOut: [CGRect],
                only: Set<Int>?) -> [Int: Label] {
        var made: [Int: (GraphicsContext.ResolvedText, CGSize, [(Mark, Color, GraphicsContext.ResolvedText)])] = [:]
        var requests: [MapLabels.Request] = []
        let rowHeight = 12.0
        for (i, s) in scene.sites.enumerated() where bounds.contains(s.point) && !s.title.isEmpty && (only?.contains(i) ?? true) {
            let trouble = s.mark == .down || s.mark == .degraded
            guard detail != .marks || trouble else { continue }
            let color: Color = vibrant ? p.l1 : trouble ? p.l1 : p.l2
            // With room for marks alone, a place is named by its first.
            let name = detail == .marks ? s.shortTitle : s.title
            let title = ctx.resolve(Text(name).font(t.font(10, trouble ? .semibold : .medium)).foregroundStyle(color))
            let ts = title.measure(in: CGSize(width: 160, height: 20))
            var rows: [(Mark, Color, GraphicsContext.ResolvedText)] = []
            if nodes {
                let nodes = Mark.troubleFirst(s.nodes.filter { !$0.isColo }, by: \.mark)
                let shown = nodes.count > 3 ? Array(nodes.prefix(2)) : nodes
                for n in shown {
                    rows.append((n.mark, markColor(n.mark),
                                 ctx.resolve(Text(n.name).font(t.font(9)).foregroundStyle(p.l3))))
                }
                if nodes.count > shown.count {
                    let rest = Array(nodes.dropFirst(shown.count))
                    rows.append((rest[0].mark, markColor(rest[0].mark),
                                 ctx.resolve(Text(tr("+\(rest.count) more")).font(t.font(9)).foregroundStyle(p.l3))))
                }
            }
            let widths = rows.map { $0.2.measure(in: CGSize(width: 160, height: 20)).width + 10 }
            let w = min(150, max(ts.width, widths.max() ?? 0))
            let size = CGSize(width: w, height: ts.height + Double(rows.count) * rowHeight)
            made[i] = (title, ts, rows)
            requests.append(.init(site: i, point: s.point, size: size, trouble: trouble))
        }
        let marks = scene.sites.map { ($0.point, r + 2) }
        var lines: [CGPoint] = []
        for arc in scene.arcs { for k in 1..<12 { lines.append(arc.point(at: Double(k) / 12)) } }
        let seams = scene.seams.map { CGRect(x: $0.x - 24, y: 0, width: 48, height: 14) }
        let placed = MapLabels.place(requests, marks: marks, lines: lines, keepOut: seams + keepOut, bounds: bounds, gap: 4, radius: r,
                                     force: detail != .marks)
        var out: [Int: Label] = [:]
        for (i, rect) in placed {
            guard let (title, ts, rows) = made[i] else { continue }
            let left = rect.midX >= scene.sites[i].point.x - 1
            out[i] = Label(rect: rect, title: title, titleSize: ts, rows: rows.map { ($0.0, $0.1, $0.2) }, rowHeight: rowHeight,
                           markSize: 6.5, leftAligned: left, on: p.on)
        }
        return out
    }

    // MARK: helpers

    /// The classic ordered-dither threshold matrix, 0 … 1.
    static let bayer8: [[Double]] = {
        let b = [[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26], [12, 44, 4, 36, 14, 46, 6, 38],
                 [60, 28, 52, 20, 62, 30, 54, 22], [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
                 [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]
        return b.map { $0.map { (Double($0) + 0.5) / 64 } }
    }()

    static func bayer(_ i: Int, _ j: Int) -> Double { bayer8[((j % 8) + 8) % 8][((i % 8) + 8) % 8] }

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }
}
