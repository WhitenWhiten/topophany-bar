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
        !value.sources.isEmpty && value.sources.allSatisfy { $0.adapter == "beszel" } ? "Beszel" : tr("Direct")
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
extension Origin {
    public var badge: String { adapter == "beszel" ? "Beszel" : tr("Source") }
    /// "Beszel · Home", or the source's name alone when it already says Beszel.
    public var detail: String {
        name.localizedCaseInsensitiveContains(badge) ? name : Words.join([badge, name])
    }
}
