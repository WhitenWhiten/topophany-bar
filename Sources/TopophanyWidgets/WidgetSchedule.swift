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
        if h.isDirect { return directDeadline(h, server: nil) }
        return h.writtenAt.addingTimeInterval(h.heartbeat + grace)
    }

    /// Only the rows used by this widget bound its snapshot, with nested resource deadlines.
    public static func directDeadline(_ h: Handoff, server node: String?) -> Date {
        guard h.engineRunning, let frame = h.decodedFrame, frame.source == "direct" else { return h.writtenAt }
        let rows = frame.rows.filter { row in
            if let node { return row.metric == "server.card" && row.select?.node == node }
            return row.metric == "sources.status" || row.metric == "servers.list"
        }
        guard !rows.isEmpty else { return h.writtenAt }
        var deadlines: [Date] = []
        for row in rows {
            guard let until = row.validUntil else { return h.writtenAt }
            deadlines.append(until)
            if case .serverCard(let card) = row.value {
                for resource in card.resources {
                    guard let until = resource.validUntil else { return h.writtenAt }
                    deadlines.append(until)
                }
            }
        }
        return deadlines.min() ?? h.writtenAt
    }

    /// A Time zones widget's clocks are set by its entries, one a minute:
    /// WidgetKit keeps no other time of another zone's live.
    public static let zonesStep: TimeInterval = 60
    /// How far ahead its entries reach: twice the heartbeat, so a reload
    /// comes well before the last. Past it, the time isn't known.
    public static let zonesSpan: TimeInterval = 2 * heartbeat

    /// A Time zones widget's entries: one at each minute, current until the
    /// next heartbeat plus the grace and history after it, the clocks going
    /// on. Past the span, places and offsets alone, the clocks "—".
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
        if stale > now, stale < end { dates.insert(stale) }
        let panel = h.zonesPanelBuilder(here: here)
        var out = dates.sorted().map { d -> (date: Date, panel: PanelModel, isCurrent: Bool) in
            let p = panel(d)
            return d < stale ? (d, p, true) : (d, p.withheld(at: d), false)
        }
        var last = panel(end).withheld(at: end)
        last.sections = last.sections.map { s in
            guard case .zones(var z) = s else { return s }
            z.isLongPast = true
            return .zones(z)
        }
        out.append((end, last, false))
        return out
    }

    /// The two entries of a reload: now, then not current. A Server widget
    /// passes its node, and a Service widget its service.
    public static func entries(_ h: Handoff?, at now: Date, server node: String? = nil, service: String? = nil)
        -> [(date: Date, panel: PanelModel, isCurrent: Bool)] {
        guard let h else {
            let empty = SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: now), engine: .stopped,
                                                        settings: TopophanyKit.Settings()))
            return [(now, empty.withheld(at: now), false)]
        }
        if h.isDirect {
            let stale = directDeadline(h, server: node)
            let panel = node.map { h.panel(server: $0, at: now) } ?? h.panel(at: now)
            guard stale > now else { return [(now, panel.withheld(at: now), false)] }
            return [(now, panel, true), (stale, (node.map { h.panel(server: $0, at: stale) } ?? h.panel(at: stale)).withheld(at: stale), false)]
        }
        let panel = node.map { h.panel(server: $0) } ?? service.map { h.panel(service: $0) } ?? h.panel()
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
        if let sources = p.status.sources {
            parts.append("sources:\(sources.isCurrent):\(sources.value.state)")
            parts += sources.value.sources.map { "source:\($0.id)=\($0.state):\($0.code ?? "")" }
        }
        if let s = p.seen { parts.append("seen:" + (s.problems?.map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",") ?? "?")) }
        if let a = p.attention { parts.append("att:\(a.total):" + a.items.prefix(3).map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")) }
        if let a = p.applications { parts.append("apps:" + a.rows.map { "\($0.id)=\($0.mark.rawValue)" }.joined(separator: ",")) }
        parts += p.services.map { "svc:\($0.id)=\($0.mark.rawValue)" }
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
