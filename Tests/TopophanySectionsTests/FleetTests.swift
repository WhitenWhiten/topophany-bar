import Foundation
import Testing
@testable import TopophanySections
import TopophanyEngine
import TopophanyKit

@Suite struct FleetTests {
    init() { L10n.force("en") }

    /// Edges and platforms first, each on its own; then servers by provider,
    /// each provider where its first server was; every mark `topo`'s.
    @Test func byWhoRunsIt() throws {
        let f = try #require(zonesPanel(.incidents).fleet)
        #expect(f.isCurrent)
        #expect(f.edges.map(\.title) == ["Cloudflare", "Vercel", "Supabase"])
        #expect(f.edges.map(\.kind) == ["edge", "edge", "platform"])
        #expect(f.servers.map(\.title) == ["Home", "Vultr", "BandwagonHost", "Oracle", "Azure", "Hetzner", "GCP"])
        #expect(f.servers.map(\.nodes.count) == [3, 2, 1, 2, 1, 1, 1])
        #expect(f.nodeCount == 14)
        #expect(f.providerCount == 10)
        let bwh = try #require(f.servers.first { $0.title == "BandwagonHost" })
        #expect(bwh.nodes.map(\.mark) == [.degraded])
        #expect(bwh.nodes.first?.note == "affected")
        // Nothing is added up: the group is the nodes, no mark of its own.
        #expect(f.servers.first { $0.title == "Oracle" }?.nodes.map(\.mark) == [.up, .up])
    }

    /// Groups left out for room show their trouble first, each node with
    /// its own mark.
    @Test func troubleFirstForGroupsLeftOut() throws {
        let f = try #require(zonesPanel(.incidents).fleet)
        let nodes = FleetSection.troubleFirst(f.servers)
        #expect(nodes.count == 11)
        #expect(nodes.first?.name == "BandwagonHost LA")
        #expect(nodes.first?.mark == .degraded)
        // The rest keep the list's order.
        #expect(nodes.dropFirst().map(\.id) == f.servers.flatMap(\.nodes).filter { $0.mark != .degraded }.map(\.id))
    }

    /// The last list, every mark withheld, while nothing current is known.
    @Test func offlineKeepsTheNamesOnly() throws {
        let f = try #require(zonesPanel(.offline).fleet)
        #expect(!f.isCurrent)
        #expect(f.nodeCount == 14)
        #expect(f.groups.allSatisfy { $0.nodes.allSatisfy { $0.mark == .offline } })
    }

    /// Without a list from `topo`, the pinned servers' cards stand in.
    @Test func pinnedServersStandIn() throws {
        let f = try #require(zonesPanel(.incidents, listServers: false).fleet)
        #expect(f.servers.map(\.title) == ["Oracle", "BandwagonHost"])
        #expect(f.edges.isEmpty)
        let none = zonesPanel(.incidents, listServers: false) { $0.sections.serverNodes = [] }
        #expect(none.fleet == nil)
        let off = zonesPanel(.incidents) { $0.sections.fleet = false }
        #expect(off.fleet == nil)
    }

    /// A node that names no provider stands alone, by its own name and kind;
    /// a provider's other names are the same provider.
    @Test func groupsByProvidersNames() {
        func node(_ id: String) -> FleetSection.Node { .init(id: id, name: id, place: "", mark: .up) }
        let f = FleetSection.grouping([(node("a"), "host", "do"), (node("b"), "router", ""), (node("c"), "host", "DigitalOcean"),
                                       (node("d"), "edge", "cloudflare"), (node("e"), "host", "my rack"), (node("f"), "host", "My-Rack")],
                                      isCurrent: true)
        #expect(f.groups.map(\.title) == ["d", "DigitalOcean", "b", "my rack"])
        #expect(f.groups.map(\.nodes.count) == [1, 2, 1, 2])
        #expect(f.groups[2].provider.isEmpty && f.groups[2].kind == "router")
        #expect(f.providerCount == 3)
    }

    @Test func notCurrentWidgetsWithholdIt() throws {
        let p = zonesPanel(.incidents).withheld(at: origin.addingTimeInterval(3600))
        let f = try #require(p.fleet)
        #expect(!f.isCurrent)
        #expect(f.groups.allSatisfy { $0.nodes.allSatisfy { $0.mark == .offline } })
    }
}
