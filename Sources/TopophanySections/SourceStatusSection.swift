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
    public var title: String {
        guard isCurrent else { return tr("Not current") }
        let label = !value.sources.isEmpty && value.sources.allSatisfy { $0.adapter == "beszel" } ? "Beszel" : tr("Sources")
        return Words.join([label, SourceMessages.state(value.state)])
    }
    public var subtitle: String {
        guard isCurrent else { return tr("Resource snapshot expired. Open the bar to update.") }
        func n(_ v: Int?) -> String { v.map(String.init) ?? "—" }
        return tr("\(n(value.counts?.current)) current · \(n(value.counts?.stale)) stale · \(n(value.counts?.missing)) without samples")
    }
    public func state(_ source: SourcesStatus.Source) -> String {
        isCurrent ? SourceMessages.state(source.state) : tr("Not current")
    }
    public func mark(_ source: SourcesStatus.Source) -> Mark {
        guard isCurrent else { return .offline }
        return source.state == "connected" ? .up : .unknown
    }
}
extension Origin {
    public var badge: String { adapter == "beszel" ? "Beszel" : tr("Source") }
    public var detail: String { Words.join([badge, name]) }
}
