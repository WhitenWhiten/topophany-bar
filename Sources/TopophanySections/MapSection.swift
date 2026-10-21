import Foundation
import TopophanyKit

/// Map: where the nodes are, and what joins them (DESIGN.md §4.3). Every
/// mark and every line is `topo`'s (`map.graph`); the app only places them.
/// Without `map.graph`, the places `servers.list` names, with each server's
/// mark and no lines, since nothing says how they connect.
public struct MapSection: Sendable, Hashable {
    public typealias Frame = Sections.MapFrame

    /// Where a node is, in degrees.
    public struct Coordinate: Sendable, Hashable {
        public var lat: Double
        public var lon: Double

        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    public struct Node: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var kind: String
        public var provider: String
        /// The node it's hosted in, or "".
        public var parent: String
        /// Where it is, as `topo` names it: "Los Angeles", or "".
        public var place: String
        /// Nil when it has no location.
        public var coordinate: Coordinate?
        public var mark: Mark
        /// A colo the edge in front said it answered from: evidence of a
        /// route, never a server a check measured.
        public var isColo: Bool

        public init(id: String, name: String, kind: String = "", provider: String = "", parent: String = "", place: String,
                    coordinate: Coordinate?, mark: Mark, isColo: Bool = false) {
            self.id = id
            self.name = name
            self.kind = kind
            self.provider = provider
            self.parent = parent
            self.place = place
            self.coordinate = coordinate
            self.mark = mark
            self.isColo = isColo
        }
    }

    /// What a line may claim, as `topo` sent it, or withheld while nothing
    /// current is known.
    public enum Line: String, Sendable, Hashable {
        /// Its own checks pass.
        case up
        /// Not measured itself; a declared path over it succeeds.
        case carried
        /// On a failing path; the faulty segment isn't established.
        case affected
        case degraded
        case down
        case unknown
        case withheld

        /// The more it needs a look, the higher.
        public var rank: Int {
            switch self {
            case .down: 5
            case .degraded: 4
            case .affected: 3
            case .up, .carried: 2
            case .unknown: 1
            case .withheld: 0
            }
        }
    }

    public struct Edge: Sendable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable {
            /// A declared link.
            case link
            /// A hop a declared path implies: an expectation, not a link.
            case path
            /// An edge or a proxy in front of an endpoint.
            case via
            /// Between an observer, a colo and the edge it fronts.
            case colo
        }

        public var id: String
        public var from: String
        public var to: String
        public var kind: Kind
        public var line: Line

        public init(id: String, from: String, to: String, kind: Kind, line: Line) {
            self.id = id
            self.from = from
            self.to = to
            self.kind = kind
            self.line = line
        }
    }

    public enum Source: Sendable, Hashable {
        /// `map.graph`: every node and line as the TUI's maps draw them.
        case graph
        /// `servers.list`'s places, where their names say.
        case places
    }

    public var nodes: [Node]
    public var edges: [Edge]
    public var source: Source
    /// Shown from the last value with every mark withheld.
    public var isCurrent: Bool
    public var frame: Frame
    /// `topo` found the graph too large to draw.
    public var isTooLarge: Bool

    public init(nodes: [Node], edges: [Edge], source: Source = .graph, isCurrent: Bool = true,
                frame: Frame = .fit, isTooLarge: Bool = false) {
        self.nodes = nodes
        self.edges = edges
        self.source = source
        self.isCurrent = isCurrent
        self.frame = frame
        self.isTooLarge = isTooLarge
    }

    /// Nodes with a location, the colos among them.
    public var placed: [Node] { nodes.filter { $0.coordinate != nil } }
    /// Nodes without one: counted, with their marks, where the map can't
    /// put them.
    public var unplaced: [Node] { nodes.filter { $0.coordinate == nil } }
    /// The places `topo` names, each once, in its order.
    public var places: [String] {
        var out: [String] = []
        for n in placed where !n.isColo && !n.place.isEmpty && !out.contains(n.place) { out.append(n.place) }
        return out
    }

    /// Every mark withheld and every line with them: where things are stays,
    /// as history.
    public func withheld() -> MapSection {
        var m = self
        m.isCurrent = false
        m.nodes = nodes.map { var n = $0; n.mark = .offline; return n }
        m.edges = edges.filter { $0.kind != .path }.map { var e = $0; e.line = .withheld; return e }
        return m
    }
}

extension MapSection.Line {
    init(_ s: MapGraph.Signal) {
        switch s {
        case .up: self = .up
        case .carried: self = .carried
        case .affected: self = .affected
        case .degraded: self = .degraded
        case .down: self = .down
        case .unknown, .other: self = .unknown
        }
    }
}

extension Mark {
    /// A node's mark, as the TUI's maps give it its signal: carried and up
    /// a dot, affected and degraded a triangle.
    init(_ s: MapGraph.Signal) {
        switch s {
        case .up, .carried: self = .up
        case .affected, .degraded: self = .degraded
        case .down: self = .down
        case .unknown, .other: self = .unknown
        }
    }
}

extension SectionBuilder {
    // MARK: map

    /// `map.graph` as the TUI's maps draw it; without it, `servers.list`'s
    /// places, then the pinned servers' cards. `observer` is the view: a
    /// path hop is drawn when it needs a look or is that observer's own, as
    /// the TUI draws it, and a hop between two nodes on one place never.
    public static func map(_ r: Reading, sections s: Sections, observer: String) -> MapSection? {
        if let row = r.row(RowID.map) {
            if case .map(let g) = row.value { return map(g, observer: observer, sections: s) }
            if case .map(let g) = r.lastValue(of: row) { return map(g, observer: observer, sections: s).withheld() }
            if row.row.reason == "graph_too_large" {
                return MapSection(nodes: [], edges: [], frame: s.mapFrame, isTooLarge: true)
            }
        }
        var current = true
        var listed: [(id: String, name: String, kind: String, provider: String, place: String, mark: Mark)] = []
        if let row = r.row(RowID.servers), case .servers(let l) = row.value {
            listed = l.map { ($0.id, $0.name, $0.kind, $0.provider, $0.place, Mark($0.health)) }
        } else if let row = r.row(RowID.servers), case .servers(let l) = r.lastValue(of: row) {
            current = false
            listed = l.map { ($0.id, $0.name, $0.kind, $0.provider, $0.place, .offline) }
        } else {
            let cards = servers(r, nodes: s.serverNodes).filter { !$0.isMissing }
            current = !cards.contains { $0.isWithheld }
            listed = cards.map { ($0.id, $0.name, $0.kind, $0.provider, $0.place, $0.mark) }
        }
        guard !listed.isEmpty else { return nil }
        let nodes = listed.map {
            MapSection.Node(id: $0.id, name: $0.name, kind: $0.kind, provider: $0.provider, place: $0.place,
                            coordinate: MapPlaces.coordinate(for: $0.place), mark: $0.mark)
        }
        return MapSection(nodes: nodes, edges: [], source: .places, isCurrent: current, frame: s.mapFrame)
    }

    static func map(_ g: MapGraph, observer: String, sections s: Sections) -> MapSection {
        let nodes = g.nodes.map { n in
            MapSection.Node(id: n.id, name: n.name, kind: n.kind, provider: n.provider, parent: n.parent, place: n.place,
                            coordinate: n.located ? n.lat.flatMap { lat in n.lon.map { MapSection.Coordinate(lat: lat, lon: $0) } } : nil,
                            mark: Mark(n.signal), isColo: n.kind == "colo")
        }
        let edges = g.edges.compactMap { e -> MapSection.Edge? in
            let line = MapSection.Line(e.signal)
            let kind: MapSection.Edge.Kind
            switch e.kind {
            case .link: kind = .link
            case .via: kind = .via
            case .colo: kind = .colo
            case .path:
                // A hop a path implies is drawn when it needs a look, or
                // when it's the viewing observer's own path.
                guard line.rank >= MapSection.Line.affected.rank || (!observer.isEmpty && e.observer == observer) else { return nil }
                kind = .path
            case .contains, .other:
                return nil
            }
            return MapSection.Edge(id: e.id, from: e.from, to: e.to, kind: kind, line: line)
        }
        return MapSection(nodes: nodes, edges: edges, source: .graph, frame: s.mapFrame)
    }
}
