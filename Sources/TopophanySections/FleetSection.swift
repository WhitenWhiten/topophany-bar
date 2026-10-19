import Foundation
import TopophanyKit

/// Fleet: every node `topo` lists, by who runs it. Edges and platforms come
/// first, each on its own, as what stands in front of the rest; then
/// servers, a provider's together, and a node that names no provider on
/// its own. Each node keeps the mark `topo` sent it. A group has no health
/// of its own: the app adds none up.
public struct FleetSection: Sendable, Hashable {
    public struct Node: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var place: String
        public var mark: Mark
        /// `topo`'s note, "affected" or "outdated", or "".
        public var note: String

        public init(id: String, name: String, place: String, mark: Mark, note: String = "") {
            self.id = id
            self.name = name
            self.place = place
            self.mark = mark
            self.note = note
        }
    }

    public struct Group: Sendable, Hashable, Identifiable {
        /// The provider's, or the node's own where it stands alone.
        public var id: String
        /// The provider as the app writes it, or the node's name.
        public var title: String
        /// The provider as `topo` sent it, for its logo; "" for none.
        public var provider: String
        /// What an edge, a platform or a lone node is: "edge", "host".
        public var kind: String
        public var nodes: [Node]
        /// An edge or a platform.
        public var isEdge: Bool

        public init(id: String, title: String, provider: String, kind: String, nodes: [Node], isEdge: Bool) {
            self.id = id
            self.title = title
            self.provider = provider
            self.kind = kind
            self.nodes = nodes
            self.isEdge = isEdge
        }
    }

    /// Edges and platforms first.
    public var groups: [Group]
    /// Shown from the last list with every mark withheld.
    public var isCurrent: Bool

    public init(groups: [Group], isCurrent: Bool) {
        self.groups = groups
        self.isCurrent = isCurrent
    }

    public var edges: [Group] { groups.filter(\.isEdge) }
    public var servers: [Group] { groups.filter { !$0.isEdge } }
    public var nodeCount: Int { groups.reduce(0) { $0 + $1.nodes.count } }
    /// How many providers run them; a node that names none counts none.
    public var providerCount: Int {
        Set(groups.compactMap { g in
            let key = Provider.known(g.provider)?.key ?? Provider.normalized(g.provider)
            return key.isEmpty ? nil : key
        }).count
    }

    /// The nodes of groups left out for room, trouble first, so a cell that
    /// counts them shows what needs a look before what is up. Each keeps
    /// its own mark; nothing is added up.
    public static func troubleFirst(_ groups: [Group]) -> [Node] {
        Mark.troubleFirst(groups.flatMap(\.nodes), by: \.mark)
    }

    /// Every mark withheld, the names kept: history, as of the last list.
    public func withheld() -> FleetSection {
        FleetSection(groups: groups.map { g in
            var g = g
            g.nodes = g.nodes.map { Node(id: $0.id, name: $0.name, place: $0.place, mark: .offline) }
            return g
        }, isCurrent: false)
    }

    /// Nodes as `topo` listed them, grouped: edges and platforms each on
    /// their own, in `topo`'s order, then the rest by provider, each group
    /// where its first node was.
    public static func grouping(_ nodes: [(node: Node, kind: String, provider: String)], isCurrent: Bool) -> FleetSection {
        var edges: [Group] = []
        var servers: [Group] = []
        for (node, kind, provider) in nodes {
            let k = kind.lowercased()
            if k == "edge" || k == "platform" {
                edges.append(Group(id: "node:" + node.id, title: node.name, provider: provider, kind: kind, nodes: [node], isEdge: true))
                continue
            }
            let key = Provider.known(provider)?.key ?? Provider.normalized(provider)
            guard !key.isEmpty else {
                servers.append(Group(id: "node:" + node.id, title: node.name, provider: "", kind: kind, nodes: [node], isEdge: false))
                continue
            }
            if let i = servers.firstIndex(where: { $0.id == "provider:" + key }) {
                servers[i].nodes.append(node)
            } else {
                servers.append(Group(id: "provider:" + key, title: Provider.name(provider), provider: provider, kind: kind, nodes: [node],
                                     isEdge: false))
            }
        }
        return FleetSection(groups: edges + servers, isCurrent: isCurrent)
    }
}
