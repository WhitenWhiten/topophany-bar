import Foundation
import TopophanyKit

/// The Status card: what the collector concludes right now, or that
/// nothing current is known. Always first.
public struct StatusSection: Sendable, Hashable {
    /// Why nothing current is known.
    public enum Blind: Sendable, Hashable {
        /// The engine hasn't produced a frame yet.
        case starting
        /// `topo` runs, but can't read the collector (`source_unavailable`).
        case collectorUnreachable
        /// The collector's snapshot itself is too old (`source_expired`).
        case snapshotExpired
        /// The verdict row passed its `valid_until`.
        case verdictExpired
        /// `topo` stopped renewing its lease.
        case leaseLapsed
        /// The view is cached: `topo` itself has only an old snapshot.
        case cached
        /// The engine stopped, and starts again at `restartAt`.
        case engineStopped(restartAt: Date?)
        case topoNotFound
        case topoTooOld
        /// Times that can't be believed, or a schema this app doesn't read.
        case unreadable
        /// `topo` said nothing current, for another reason.
        case unknown(reason: String)
        /// A widget that the app stopped renewing: what it shows is history.
        case notCurrent
    }

    public enum Kind: Sendable, Hashable {
        case verdict(VerdictState)
        case blind(Blind)
    }

    public var kind: Kind
    /// ● ▲ ✖ ○ ◌
    public var mark: Mark
    /// `topo`'s own words for the verdict, such as "5 INCIDENTS".
    public var topoText: String
    /// Checks by health, `nil` when not known.
    public var counts: HealthCounts?
    public var paused: Int?
    public var maintenance: Int?
    public var configured: Int?
    public var incidents: Int?
    public var observersLive: Int?
    public var observersAll: Int?
    /// When the frame shown was made.
    public var updatedAt: Date?
    /// The last verdict that was current, shown as history while blind.
    public var lastKnown: LastKnown?
    public var now: Date

    public init(kind: Kind, mark: Mark, topoText: String = "", counts: HealthCounts? = nil, paused: Int? = nil,
                maintenance: Int? = nil, configured: Int? = nil, incidents: Int? = nil, observersLive: Int? = nil,
                observersAll: Int? = nil, updatedAt: Date? = nil, lastKnown: LastKnown? = nil, now: Date) {
        self.kind = kind
        self.mark = mark
        self.topoText = topoText
        self.counts = counts
        self.paused = paused
        self.maintenance = maintenance
        self.configured = configured
        self.incidents = incidents
        self.observersLive = observersLive
        self.observersAll = observersAll
        self.updatedAt = updatedAt
        self.lastKnown = lastKnown
        self.now = now
    }

    public var isBlind: Bool {
        if case .blind = kind { return true }
        return false
    }

    public var verdictState: VerdictState? {
        if case .verdict(let s) = kind { return s }
        return nil
    }

    /// The number the status item shows in Count mode: what needs
    /// attention. `nil` when nothing does, or nothing is known.
    public var count: Int? {
        guard let s = verdictState, let c = counts else { return nil }
        let n: Int?
        switch s {
        case .clear: n = nil
        case .degraded: n = c.warning
        case .incidents: n = incidents
        case .down: n = c.down
        case .incomplete, .noEvidence, .noChecks: n = c.unknown
        case .cached, .other: n = nil
        }
        return n.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The headline: "All clear", "5 incidents", "Offline".
    public var title: String {
        switch kind {
        case .verdict(let s):
            switch s {
            case .clear: return tr("All clear")
            case .degraded: return tr("Degraded")
            case .incidents: return incidents.map { tr("\($0) incidents") } ?? tr("Incidents")
            case .down: return counts?.down.map { tr("\($0) down") } ?? tr("Down")
            case .incomplete: return tr("Evidence incomplete")
            case .noEvidence: return tr("No evidence")
            case .noChecks: return tr("No checks")
            case .cached: return tr("Cached")
            case .other: return topoText.isEmpty ? tr("Unknown") : topoText.capitalized
            }
        case .blind(.starting): return tr("Starting")
        case .blind(.cached): return tr("Cached")
        case .blind(.notCurrent): return tr("Not current")
        case .blind: return tr("Offline")
        }
    }

    /// The menu bar's Words mode: "All clear", "5 incidents", "Incomplete".
    public var shortTitle: String {
        switch verdictState {
        case .incomplete?, .noEvidence?, .noChecks?: return tr("Incomplete")
        case .some: return title
        case nil: return tr("Offline")
        }
    }

    /// The line under the headline.
    public var subtitle: String {
        switch kind {
        case .verdict(let s):
            guard let c = counts, let up = c.up else { return topoText }
            let total = configured ?? 0
            switch s {
            case .clear:
                return tr("\(up) of \(total) checks passing")
            case .degraded:
                let w = c.warning ?? 0
                if let i = incidents, i > 0 { return tr("\(w) checks warning · \(i) incidents") }
                return tr("\(w) checks warning · no incidents")
            case .incidents, .down:
                return tr("\(c.down ?? 0) checks down · \(up) of \(total) passing")
            case .incomplete:
                return tr("\(c.unknown ?? 0) checks without current evidence")
            case .noEvidence:
                return tr("No check has current evidence")
            case .noChecks:
                return tr("Nothing is measured in this view")
            case .cached, .other:
                return topoText
            }
        case .blind(let b):
            return Self.reason(b, now: now)
        }
    }

    static func reason(_ b: Blind, now: Date) -> String {
        switch b {
        case .starting: return tr("Waiting for topo’s first frame")
        case .collectorUnreachable: return tr("Collector unreachable · topo keeps retrying")
        case .snapshotExpired: return tr("The collector’s snapshot is too old")
        case .verdictExpired: return tr("The verdict passed its deadline")
        case .leaseLapsed: return tr("topo stopped answering")
        case .cached: return tr("Showing the last snapshot; nothing current is known")
        case .engineStopped(let at?):
            let s = max(1, Int(at.timeIntervalSince(now).rounded(.up)))
            return tr("topo stopped · restarting in \(s) s")
        case .engineStopped(nil): return tr("topo stopped")
        case .topoNotFound: return tr("topo not found · set its path in Settings")
        case .topoTooOld: return tr("This topo has no monitor stream · upgrade it")
        case .unreadable: return tr("topo’s frame can’t be read")
        case .unknown(let r): return r.isEmpty ? tr("Nothing current is known") : tr("Nothing current is known (\(r))")
        case .notCurrent: return tr("Not renewed by topophany-bar")
        }
    }

    /// "Last snapshot 3 min ago said **all clear**. Nothing current is
    /// known." for a blind card, in Markdown.
    public var history: String {
        guard let k = lastKnown else { return tr("Nothing current is known.") }
        let said = StatusSection.words(for: k)
        return tr("Last snapshot \(Words.ago(k.at, now: now)) said **\(said)**. Nothing current is known.")
    }

    /// A past verdict in words, lowercased for a sentence: "all clear".
    public static func words(for k: LastKnown) -> String {
        switch k.verdictState {
        case .clear: tr("all clear")
        case .degraded: tr("degraded")
        case .incidents: k.incidents.map { tr("\($0) incidents").lowercased() } ?? k.text.lowercased()
        case .incomplete: tr("evidence incomplete")
        default: k.text.lowercased()
        }
    }

    /// The TUI's words for the verdict: "5 INCIDENTS", "OFFLINE".
    public var tuiTitle: String {
        switch kind {
        case .verdict(let s):
            switch s {
            case .clear: return tr("ALL CLEAR")
            case .degraded: return tr("DEGRADED")
            case .incidents: return incidents.map { tr("\($0) INCIDENTS") } ?? topoText
            case .down: return counts?.down.map { tr("\($0) DOWN") } ?? topoText
            case .incomplete: return tr("INCOMPLETE EVIDENCE")
            case .noEvidence: return tr("NO EVIDENCE")
            case .noChecks: return tr("NO CHECKS")
            case .cached: return tr("CACHED")
            case .other: return topoText.uppercased()
            }
        case .blind(.starting): return tr("STARTING")
        case .blind(.cached): return tr("CACHED")
        case .blind(.notCurrent): return tr("NOT CURRENT")
        case .blind: return tr("OFFLINE")
        }
    }

    /// "Last known: 5 incidents", or what to say when nothing was.
    public var lastKnownLine: String {
        guard let k = lastKnown else { return tr("Nothing current is known") }
        return tr("Last known: \(StatusSection.words(for: k))")
    }

    /// The TUI's short words, for the menu bar chip and small widgets.
    public var tuiShortTitle: String {
        verdictState == .incomplete ? tr("INCOMPLETE") : tuiTitle
    }

    /// The TUI's big number and the two lines beside it.
    public var big: (digits: String, top: String, bottom: String) {
        let of = configured.map { tr("of \($0) configured") } ?? ""
        guard let s = verdictState, let c = counts else {
            let last = lastKnown.map { tr("last snapshot \(Words.ago($0.at, now: now))") } ?? tr("nothing current is known")
            switch kind {
            case .blind(.collectorUnreachable): return ("--", tr("collector unreachable"), last)
            case .blind(.starting): return ("--", tr("starting topo"), "")
            case .blind(.engineStopped), .blind(.topoNotFound), .blind(.topoTooOld): return ("--", tr("topo not running"), last)
            case .blind(.notCurrent):
                return ("--", tr("not current"), lastKnown.map { tr("last known \(Words.ago($0.at, now: now))") } ?? "")
            default: return ("--", tr("not current"), last)
            }
        }
        switch s {
        case .clear: return (c.up.map(String.init) ?? "--", tr("checks passing"), of)
        case .degraded: return (c.warning.map(String.init) ?? "--", tr("checks warning"), of)
        case .incidents, .down:
            let failing = (c.down ?? 0) + (c.warning ?? 0)
            return (String(failing), tr("checks failing"), of)
        case .incomplete, .noEvidence, .noChecks: return (c.unknown.map(String.init) ?? "--", tr("checks unknown"), of)
        case .cached, .other: return ("--", topoText.lowercased(), of)
        }
    }
}
