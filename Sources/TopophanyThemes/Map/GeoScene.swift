import CoreGraphics
import Foundation
import TopophanySections

/// How the map is magnified and moved: a point of the framed map at `p`
/// shows at `p × zoom + offset`. At 1× it is the framing itself.
public struct MapTransform: Sendable, Hashable {
    public var zoom: Double
    public var offset: CGPoint

    public init(zoom: Double = 1, offset: CGPoint = .zero) {
        self.zoom = zoom
        self.offset = offset
    }

    public static let identity = MapTransform()

    func apply(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + offset.x, y: p.y * zoom + offset.y) }
    func invert(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - offset.x) / zoom, y: (p.y - offset.y) / zoom) }

    /// Kept so the magnified map always covers the view: never smaller than
    /// the framing, never moved off its edges.
    func clamped(to size: CGSize, maxZoom: Double) -> MapTransform {
        let z = min(max(zoom, 1), maxZoom)
        return MapTransform(zoom: z, offset: CGPoint(x: min(0, max(size.width - size.width * z, offset.x)),
                                                     y: min(0, max(size.height - size.height * z, offset.y))))
    }

    /// Magnified by `factor` about `anchor`, which stays where it is.
    func zoomed(by factor: Double, about anchor: CGPoint) -> MapTransform {
        let base = invert(anchor)
        let z = zoom * factor
        return MapTransform(zoom: z, offset: CGPoint(x: anchor.x - base.x * z, y: anchor.y - base.y * z))
    }
}

/// The geo map laid out in a view: the framing, each site (nodes that share
/// a place, or would sit on one another) and the arcs between them, as the
/// TUI's geo map lays them out. Shared by both renderers: units are the
/// map's, y down.
struct GeoScene {
    struct Site {
        var point: CGPoint
        var nodes: [MapSection.Node]
        /// What needs the most attention among its nodes, as the TUI's
        /// sites carry it.
        var mark: Mark
        /// Its places: "Seattle", "Los Angeles · Irvine", "Tokyo +2".
        var title: String
        /// Its first place, and how many more: "Los Angeles +1".
        var shortTitle = ""
        /// Holds only colos an edge reported, drawn hollow.
        var coloOnly: Bool
    }

    struct Arc {
        var a: Int
        var b: Int
        var line: MapSection.Line
        /// Declared by a link; otherwise implied by a path, an edge in
        /// front or a reported colo, and dashed.
        var declared: Bool
        var start: CGPoint
        var control: CGPoint
        var end: CGPoint

        func point(at t: Double) -> CGPoint {
            let m = 1 - t
            return CGPoint(x: m * m * start.x + 2 * m * t * control.x + t * t * end.x,
                           y: m * m * start.y + 2 * m * t * control.y + t * t * end.y)
        }
    }

    var view: GeoView
    var size: CGSize
    var transform: MapTransform
    var sites: [Site]
    var arcs: [Arc]
    /// Nodes the map can't place.
    var unplaced: [MapSection.Node]

    /// - Parameters:
    ///   - samePlace: how far apart two nodes of one place may be and still
    ///     share a site.
    ///   - collide: how close two sites may come before they merge.
    init(_ map: MapSection, size: CGSize, ky: Double = 1, transform: MapTransform = .identity,
         samePlace: Double = 60, collide: CGSize = CGSize(width: 12, height: 10)) {
        self.size = size
        self.transform = transform
        let placed = map.nodes.filter { $0.coordinate != nil }
        view = GeoView.framing(placed.compactMap(\.coordinate), width: size.width, height: size.height, ky: ky, frame: map.frame)
        unplaced = map.nodes.filter { $0.coordinate == nil }
        // Nodes that share a declared place become one site; so do nodes
        // close enough that their marks would collide.
        var sites: [Site] = []
        var places: [[String]] = []
        var cities: [[String]] = []
        var points: [[CGPoint]] = []
        for n in placed {
            guard let c = n.coordinate else { continue }
            let p = transform.apply(view.project(c))
            let k = sites.indices.first { i in
                let s = sites[i]
                let dx = abs(s.point.x - p.x), dy = abs(s.point.y - p.y)
                return (!n.place.isEmpty && (places[i].contains(n.place) || cities[i].contains(n.place)) && dx < samePlace && dy < samePlace)
                    || (dx <= collide.width && dy <= collide.height)
            }
            let i: Int
            if let k {
                i = k
            } else {
                sites.append(Site(point: p, nodes: [], mark: .offline, title: "", coloOnly: true))
                places.append([])
                cities.append([])
                points.append([])
                i = sites.count - 1
            }
            // A colo is named by its edge's city, which spells a declared
            // place its own way: it names a site only when nothing declared
            // there names it.
            if !n.place.isEmpty {
                if n.isColo {
                    if !cities[i].contains(n.place) { cities[i].append(n.place) }
                } else if !places[i].contains(n.place) {
                    places[i].append(n.place)
                }
            }
            sites[i].nodes.append(n)
            sites[i].coloOnly = sites[i].coloOnly && n.isColo
            points[i].append(p)
            sites[i].mark = Self.worse(sites[i].mark, n.mark, first: sites[i].nodes.count == 1)
        }
        for i in sites.indices {
            let ps = points[i]
            sites[i].point = CGPoint(x: ps.map(\.x).reduce(0, +) / Double(ps.count), y: ps.map(\.y).reduce(0, +) / Double(ps.count))
            let names = places[i].isEmpty ? cities[i] : places[i]
            sites[i].title = switch names.count {
            case 0: Self.coordinates(sites[i].nodes[0].coordinate)
            case 1: names[0]
            case 2: names[0] + " · " + names[1]
            default: names[0] + " +\(names.count - 1)"
            }
            sites[i].shortTitle = names.count > 1 ? names[0] + " +\(names.count - 1)" : sites[i].title
        }
        self.sites = sites

        // One arc per pair of sites, carrying the line that needs the most
        // attention; drawn solid when a link declares it.
        var siteOf: [String: Int] = [:]
        for (i, s) in sites.enumerated() { for n in s.nodes { siteOf[n.id] = i } }
        var byPair: [[Int]: (line: MapSection.Line, declared: Bool)] = [:]
        var order: [[Int]] = []
        for e in map.edges {
            guard let a = siteOf[e.from], let b = siteOf[e.to], a != b else { continue }
            let key = [min(a, b), max(a, b)]
            if let x = byPair[key] {
                byPair[key] = (e.line.rank > x.line.rank ? e.line : x.line, x.declared || e.kind == .link)
            } else {
                byPair[key] = (e.line, e.kind == .link)
                order.append(key)
            }
        }
        arcs = order.compactMap { key in
            guard let x = byPair[key] else { return nil }
            let p0 = sites[key[0]].point, p3 = sites[key[1]].point
            let dx = p3.x - p0.x, dy = p3.y - p0.y
            let l = (dx * dx + dy * dy).squareRoot()
            guard l >= 6 else { return nil }
            // Every arc bows toward the top of the map, like a flight path.
            var nx = -dy / l, ny = dx / l
            if ny > 0 { (nx, ny) = (-nx, -ny) }
            let bow = min(l * 0.22, size.height * 0.3)
            let control = CGPoint(x: (p0.x + p3.x) / 2 + nx * bow, y: (p0.y + p3.y) / 2 + ny * bow)
            return Arc(a: key[0], b: key[1], line: x.line, declared: x.declared, start: p0, control: control, end: p3)
        }
    }

    /// The mark that needs the more attention, as the TUI's maps rank
    /// signals: down, then warn, then up, then unknown.
    static func worse(_ a: Mark, _ b: Mark, first: Bool) -> Mark {
        func rank(_ m: Mark) -> Int {
            switch m {
            case .down: 5
            case .degraded: 4
            case .up: 2
            case .unknown: 1
            case .offline: 0
            }
        }
        if first { return b }
        return rank(b) > rank(a) ? b : a
    }

    static func coordinates(_ c: MapSection.Coordinate?) -> String {
        guard let c else { return "" }
        func part(_ v: Double, _ pos: String, _ neg: String) -> String { String(format: "%.0f°", abs(v)) + (v < 0 ? neg : pos) }
        return part(c.lat, "N", "S") + " " + part(c.lon, "E", "W")
    }

    /// Whether the land covers the map at `p`, a point of the view.
    func isLand(_ p: CGPoint) -> Bool {
        let b = transform.invert(p)
        guard let g = view.at(b.x, b.y) else { return false }
        return LandMask.isLand(g.lat, g.lon)
    }

    /// How much of the `w` × `h` box centred on `p` is land, from `n` × `n`
    /// samples.
    func land(around p: CGPoint, width w: Double, height h: Double, samples n: Int) -> Double {
        var hits = 0
        for j in 0..<n {
            for i in 0..<n {
                let q = CGPoint(x: p.x - w / 2 + (Double(i) + 0.5) * w / Double(n), y: p.y - h / 2 + (Double(j) + 0.5) * h / Double(n))
                if isLand(q) { hits += 1 }
            }
        }
        return Double(hits) / Double(n * n)
    }

    /// Each fold's seam on the view: where it runs, and how many degrees of
    /// longitude it holds.
    var seams: [(x: Double, degrees: Int)] {
        view.seams.map { (transform.apply(CGPoint(x: $0.x, y: 0)).x, $0.degrees) }
    }

    /// Whether `p` lies on the framed world, not off its edge or in a seam.
    func onWorld(_ p: CGPoint) -> Bool {
        let b = transform.invert(p)
        return view.at(b.x, b.y) != nil
    }

    /// Sites outside the view that need a look, each pinned to the view's
    /// edge toward it, `inset` in, so trouble moved out of sight still shows.
    func offView(inset: Double) -> [(site: Int, point: CGPoint)] {
        let r = CGRect(origin: .zero, size: size)
        return sites.indices.compactMap { i in
            let s = sites[i]
            guard !r.contains(s.point), s.mark == .down || s.mark == .degraded else { return nil }
            return (i, CGPoint(x: min(max(s.point.x, inset), size.width - inset), y: min(max(s.point.y, inset), size.height - inset)))
        }
    }
}

/// Places each site's label beside its mark, where it covers no other
/// label, mark or seam and stays inside the view, trouble first. A label
/// that finds no place is left out, except trouble's, which takes the place
/// that covers least.
enum MapLabels {
    struct Request {
        var site: Int
        var point: CGPoint
        var size: CGSize
        /// Needs a look: placed first, and always.
        var trouble: Bool
    }

    /// - Parameters:
    ///   - marks: every mark on the map, as its centre and radius.
    ///   - lines: points along the arcs, to keep clear of where possible.
    ///   - gap: between a mark's edge and its label.
    ///   - force: trouble's label takes the place that covers least when none
    ///     is clear.
    static func place(_ requests: [Request], marks: [(CGPoint, Double)], lines: [CGPoint], keepOut: [CGRect] = [],
                      bounds: CGRect, gap: Double, radius: Double, force: Bool = true) -> [Int: CGRect] {
        var placed: [Int: CGRect] = [:]
        var taken = keepOut
        let order = requests.sorted { a, b in
            if a.trouble != b.trouble { return a.trouble }
            return a.point.y < b.point.y
        }
        for r in order {
            let c = r.point, w = r.size.width, h = r.size.height, g = radius + gap
            let candidates = [
                CGRect(x: c.x + g, y: c.y - h / 2, width: w, height: h),
                CGRect(x: c.x - g - w, y: c.y - h / 2, width: w, height: h),
                CGRect(x: c.x - w / 2, y: c.y - g - h + 1, width: w, height: h),
                CGRect(x: c.x - w / 2, y: c.y + g - 1, width: w, height: h),
                CGRect(x: c.x + g * 0.6, y: c.y - g * 0.6 - h, width: w, height: h),
                CGRect(x: c.x + g * 0.6, y: c.y + g * 0.6, width: w, height: h),
                CGRect(x: c.x - g * 0.6 - w, y: c.y - g * 0.6 - h, width: w, height: h),
                CGRect(x: c.x - g * 0.6 - w, y: c.y + g * 0.6, width: w, height: h),
            ]
            var best: (CGRect, Double)?
            for (k, rect) in candidates.enumerated() {
                var cost = Double(k)
                if !bounds.contains(rect) { cost += 1000 }
                if taken.contains(where: { $0.insetBy(dx: -2, dy: -1).intersects(rect) }) { cost += 500 }
                for (m, mr) in marks where !(m.x == c.x && m.y == c.y) && rect.insetBy(dx: -mr, dy: -mr).contains(m) { cost += 300 }
                cost += Double(lines.count { rect.contains($0) }) * 3
                if best.map({ cost < $0.1 }) ?? true { best = (rect, cost) }
            }
            guard let (rect, cost) = best else { continue }
            if cost >= 300 && !(r.trouble && force) { continue }
            if cost >= 1000 { continue }
            placed[r.site] = rect
            taken.append(rect)
        }
        return placed
    }
}
