import Foundation
import TopophanyKit
import TopophanySections

/// When widgets reload, and when they stop claiming the present
/// (DESIGN.md §7.2 and §7.3).
public enum WidgetSchedule {
    /// Renewed this often while nothing changes.
    public static let heartbeat: TimeInterval = 30 * 60
    /// How long past a missed renewal a widget still shows its entry as now.
    public static let grace: TimeInterval = 15 * 60

    /// The "Not current" entry's date: the next heartbeat plus the grace.
    public static func notCurrent(after h: Handoff) -> Date {
        h.writtenAt.addingTimeInterval(h.heartbeat + grace)
    }

    /// The two entries of a reload: now, then not current.
    public static func entries(_ h: Handoff?, at now: Date) -> [(date: Date, panel: PanelModel, isCurrent: Bool)] {
        guard let h else {
            let empty = SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: now), engine: .stopped,
                                                        settings: TopophanyKit.Settings()))
            return [(now, empty.withheld(at: now), false)]
        }
        let panel = h.panel()
        let stale = notCurrent(after: h)
        if stale <= now { return [(now, panel.withheld(at: now), false)] }
        return [(now, panel, true), (stale, panel.withheld(at: stale), false)]
    }
}

/// Decides when the app asks WidgetKit to reload: at once when the verdict
/// changes or a row a widget shows changes health, else on the heartbeat.
public struct WidgetReloadPolicy: Sendable {
    public private(set) var lastSignature: String?
    public private(set) var lastReload: Date?

    public init() {}

    /// What widgets show, as healths only: the verdict, every list row and
    /// every server, by ID.
    public static func signature(_ p: PanelModel) -> String {
        var parts = ["status:\(p.status.kind):\(p.status.mark.rawValue):\(p.status.count ?? -1)"]
        if let s = p.seen { parts.append("seen:" + (s.problems?.map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",") ?? "?")) }
        if let a = p.attention { parts.append("att:\(a.total):" + a.items.prefix(3).map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")) }
        if let a = p.applications { parts.append("apps:" + a.rows.map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")) }
        parts += p.servers.map { "srv:\($0.id)=\($0.mark.rawValue)" }
        if case .server(let c, _)? = p.mac { parts.append("mac:\(c.id)=\(c.mark.rawValue)") }
        return parts.joined(separator: "|")
    }

    /// Whether to reload now, recording it if so.
    public mutating func shouldReload(_ p: PanelModel, at now: Date) -> Bool {
        let sig = Self.signature(p)
        let due = lastReload.map { now.timeIntervalSince($0) >= WidgetSchedule.heartbeat } ?? true
        guard sig != lastSignature || due else { return false }
        lastSignature = sig
        lastReload = now
        return true
    }
}
