import Foundation
import TopophanyKit

/// Presentation of Go's acquisition state. Counts and classifications are never inferred here.
public struct SourceStatusSection: Sendable, Hashable {
    public var value: SourcesStatus
    public var isCurrent: Bool
    public var snapshotAt: Date?
    public var mark: Mark {
        guard isCurrent else { return .offline }
        switch value.state { case "ready": return .up; case "partial": return .degraded; default: return .unknown }
    }
    /// The headline, the state alone: "Connected", "Needs attention".
    public var title: String {
        guard isCurrent else { return tr("Not current") }
        return SourceMessages.headline(value.state)
    }
    /// Who the sources are: "Beszel", or "Direct" when they're mixed.
    public var adapter: String {
        let names = Set(value.sources.map { Origin.name(adapter: $0.adapter) })
        guard names.count == 1, let name = names.first, let known = name else { return tr("Direct") }
        return known
    }
    /// "3 of 3 servers current", or what isn't: "1 of 2 current · 1 without samples".
    public var subtitle: String {
        guard isCurrent else { return tr("Snapshot expired") }
        guard let c = value.counts, let current = c.current else { return tr("Resource counts not known") }
        if c.selected == 0 { return tr("No servers selected") }
        let rest = rest(c)
        guard let selected = c.selected else { return Words.join([tr("\(current) current")] + rest) }
        return rest.isEmpty ? tr("\(current) of \(selected) servers current") : Words.join([tr("\(current) of \(selected) current")] + rest)
    }
    /// "1 stale", "1 without samples": only those there are.
    func rest(_ c: SourcesStatus.Counts) -> [String] {
        var parts: [String] = []
        if let s = c.stale, s > 0 { parts.append(tr("\(s) stale")) }
        if let m = c.missing, m > 0 { parts.append(tr("\(m) without samples")) }
        return parts
    }
    /// The TUI's lines beside the big number of current servers.
    public var big: (digits: String, top: String, bottom: String) {
        guard isCurrent, let c = value.counts, let current = c.current else { return ("--", tr("servers current"), subtitle) }
        let top = c.selected.map { tr("of \($0) servers current") } ?? tr("servers current")
        let rest = rest(c)
        return ("\(current)", top, rest.isEmpty ? sourceCount : Words.join(rest))
    }
    /// "2 sources", as `topo` counts them.
    public var sourceCount: String {
        tr("\(value.counts?.sources ?? value.sources.count) sources")
    }
    public func state(_ source: SourcesStatus.Source) -> String {
        isCurrent ? SourceMessages.state(source.state) : tr("Not current")
    }
    /// What a source's row ends in: its servers while it's connected,
    /// "2 of 2 current"; otherwise its state. Nothing once not current.
    public func detail(_ source: SourcesStatus.Source) -> String {
        guard isCurrent else { return "" }
        guard source.state == "connected", let c = source.counts, let current = c.current else { return state(source) }
        guard let selected = c.selected else { return tr("\(current) current") }
        return tr("\(current) of \(selected) current")
    }
    /// A source in a state that asks for something: signing in, access, a Hub that can't be reached.
    public func needsLook(_ source: SourcesStatus.Source) -> Bool {
        isCurrent && source.state != "connected" && source.state != "loading"
    }
    public func mark(_ source: SourcesStatus.Source) -> Mark {
        guard isCurrent else { return .offline }
        return source.state == "connected" ? .up : .unknown
    }
}

/// A source a collector reads servers from, such as a Komari server or a
/// Beszel Hub in its topology, as its server list names it.
public struct ListedSource: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// As `topo` sent it: "komari", "beszel".
    public var adapter: String
    /// Its servers' names, in the list's order.
    public var servers: [String]

    public init(id: String, name: String, adapter: String, servers: [String]) {
        self.id = id
        self.name = name
        self.adapter = adapter
        self.servers = servers
    }

    /// The servers listed from a source, each source once, in the order
    /// of its first server: the last list `topo` sent, current or not.
    public static func from(_ r: Reading) -> [ListedSource] {
        guard let row = r.row(TemplateCompiler.RowID.servers) else { return [] }
        let list: [ServerListEntry]
        if case .servers(let l) = row.value { list = l } else if case .servers(let l) = r.lastValue(of: row) { list = l } else { return [] }
        var out: [ListedSource] = []
        for s in list {
            guard let o = s.origin else { continue }
            if let i = out.firstIndex(where: { $0.id == o.sourceID }) {
                out[i].servers.append(s.name)
            } else {
                out.append(ListedSource(id: o.sourceID, name: o.name, adapter: o.adapter, servers: [s.name]))
            }
        }
        return out
    }
}

extension Origin {
    /// The software an adapter reads, as it names itself: "Beszel",
    /// "Komari"; `nil` for one this app doesn't know.
    public static func name(adapter: String) -> String? {
        switch adapter {
        case "beszel": "Beszel"
        case "komari": "Komari"
        default: nil
        }
    }

    public var badge: String { Self.name(adapter: adapter) ?? tr("Source") }
    /// "Beszel · Home", or the source's name alone when it already says
    /// Beszel: "Komari Monitor".
    public var detail: String {
        name.localizedCaseInsensitiveContains(badge) ? name : Words.join([badge, name])
    }
}
