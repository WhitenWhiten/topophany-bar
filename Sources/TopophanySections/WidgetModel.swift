import Foundation
import TopophanyKit

/// A widget's size: which layout it gets. `width` and `height` are the
/// design's, on a 170 pt grid with 24 pt gaps. WidgetKit's vary with the
/// display, so a renderer fills the bounds it is given.
public enum WidgetSize: String, Sendable, Hashable, CaseIterable {
    case small, medium, large, extraLarge

    public var width: Double {
        switch self {
        case .small: 170
        case .medium, .large: 364
        case .extraLarge: 752
        }
    }

    public var height: Double { self == .small || self == .medium ? 170 : 364 }
}

/// What a widget shows: the panel's own section models, cut to its size.
public struct WidgetModel: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// The verdict, and more of the panel as the size allows.
        case status
        /// One server's card; `isMac` when it is this Mac's node.
        case server(node: String, isMac: Bool)
    }

    /// The medium Status widget's right side.
    public enum Right: String, Sendable, Hashable, CaseIterable {
        /// Needs attention, or Applications when nothing needs attention.
        case automatic
        case attention
        case applications
    }

    public var kind: Kind
    public var right: Right
    public var panel: PanelModel
    /// Whether this is the current entry, or the one WidgetKit shows once
    /// the app has stopped renewing it.
    public var isCurrent: Bool

    public init(kind: Kind, right: Right = .automatic, panel: PanelModel, isCurrent: Bool = true) {
        self.kind = kind
        self.right = right
        self.panel = panel
        self.isCurrent = isCurrent
    }

    public var status: StatusSection { panel.status }

    /// The server a Server widget shows: a pinned server, or This Mac's.
    public var server: ServerCardModel? {
        guard case .server(let node, _) = kind else { return nil }
        if case .server(let c, _)? = panel.mac, c.id == node { return c }
        return panel.servers.first { $0.id == node }
    }

    public var isMac: Bool {
        if case .server(_, let mac) = kind { return mac }
        return false
    }

    /// When the frame shown was made; the age line counts up from it.
    public var updatedAt: Date? { panel.status.updatedAt ?? panel.status.lastKnown?.at }

    /// The entry dated past the next renewal: the same widget, with the
    /// last verdict shown as history and every health withheld.
    public func notCurrent(at date: Date) -> WidgetModel {
        var m = self
        m.isCurrent = false
        m.panel = panel.withheld(at: date)
        return m
    }
}

extension PanelModel {
    /// Everything as history at `date`: names stay, every health and value
    /// is withheld, and the status card says it is not current.
    public func withheld(at date: Date) -> PanelModel {
        var p = self
        let known = status.isBlind ? status.lastKnown : status.lastKnown ?? status.updatedAt.map { at in
            LastKnown(verdict: Verdict(state: status.verdictState ?? .other(""), glyph: status.mark.glyph,
                                       text: status.topoText, counts: nil, configured: status.configured,
                                       incidents: status.incidents, observers: nil), at: at)
        }
        p.status = StatusSection(kind: .blind(.notCurrent), mark: .offline, updatedAt: status.updatedAt,
                                 lastKnown: known, now: date)
        p.chrome.connection = .notRunning(tr("Not current"))
        p.chrome.now = date
        p.sections = sections.compactMap { s -> Section? in
            switch s {
            case .seen(let x): return .seen(SeenFromSection(problems: nil, calm: 0, total: x.total))
            case .attention: return nil
            case .applications(let a):
                return .applications(ApplicationsSection(rows: a.rows.map {
                    .init(id: $0.id, name: $0.name, mark: .offline, services: $0.services.map { _ in .offline },
                          note: tr("cached"), noteNeedsLook: false)
                }, isCurrent: false))
            case .servers(let cards): return .servers(cards.map { $0.withheld(at: date) })
            case .mac(.server(let c, let node)): return .mac(.server(c.withheld(at: date), node: node))
            case .mac(.local): return nil
            }
        }
        return p
    }
}

extension ServerCardModel {
    public func withheld(at date: Date) -> ServerCardModel {
        var c = self
        guard !isMissing else { return c }
        c.isWithheld = true
        c.mark = .offline
        c.pill = .cached
        c.cpu.percent = nil
        c.memory.percent = nil
        c.disk.percent = nil
        c.memory.detail = ""
        c.disk.detail = ""
        c.services = services.map { .init(id: $0.id, name: $0.name, mark: .offline, note: "") }
        c.observes = observes.map { .init(id: $0.id, name: $0.name, mark: .offline, text: tr("not known now")) }
        c.now = date
        return c
    }
}
