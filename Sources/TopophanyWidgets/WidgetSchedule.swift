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

    /// A Time zones widget's clocks read live; its day ribbons move a step
    /// this often. WidgetKit draws every entry ahead, so each one costs.
    public static let zonesStep: TimeInterval = 3600
    /// How far ahead its entries reach. Without a reload in that time, the
    /// last entry draws the clocks alone.
    public static let zonesSpan: TimeInterval = 24 * 3600

    /// A Time zones widget's entries: one each hour, and one at each zone's
    /// midnight, when its day turns; current until the next heartbeat plus
    /// the grace and history after it, the clocks going on. Past the span,
    /// the clocks alone.
    public static func zonesEntries(_ h: Handoff?, at now: Date, here: TimeZone = .autoupdatingCurrent)
        -> [(date: Date, panel: PanelModel, isCurrent: Bool)] {
        guard let h else {
            let empty = SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: now), engine: .stopped,
                                                        settings: TopophanyKit.Settings()))
            return [(now, empty.withheld(at: now), false)]
        }
        let stale = notCurrent(after: h)
        let end = now.addingTimeInterval(zonesSpan)
        let first = (now.timeIntervalSinceReferenceDate / zonesStep).rounded(.down) * zonesStep + zonesStep
        var dates = Set([now] + stride(from: first, to: end.timeIntervalSinceReferenceDate, by: zonesStep)
            .map { Date(timeIntervalSinceReferenceDate: $0) })
        let zones = WidgetModel(kind: .zones, panel: h.panel(zonesAt: now, here: here)).zones?.zones ?? []
        for zone in zones {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone.timeZone
            if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime),
               midnight < end {
                dates.insert(midnight)
            }
        }
        if stale > now, stale < end { dates.insert(stale) }
        var out = dates.sorted().map { d -> (date: Date, panel: PanelModel, isCurrent: Bool) in
            let p = h.panel(zonesAt: d, here: here)
            return d < stale ? (d, p, true) : (d, p.withheld(at: d), false)
        }
        var last = h.panel(zonesAt: end, here: here).withheld(at: end)
        last.sections = last.sections.map { s in
            guard case .zones(var z) = s else { return s }
            z.clocksOnly = true
            return .zones(z)
        }
        out.append((end, last, false))
        return out
    }

    /// The two entries of a reload: now, then not current. A Server widget
    /// passes its node.
    public static func entries(_ h: Handoff?, at now: Date, server node: String? = nil)
        -> [(date: Date, panel: PanelModel, isCurrent: Bool)] {
        guard let h else {
            let empty = SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: now), engine: .stopped,
                                                        settings: TopophanyKit.Settings()))
            return [(now, empty.withheld(at: now), false)]
        }
        let panel = node.map { h.panel(server: $0) } ?? h.panel()
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
