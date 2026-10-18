import Foundation

/// Turns settings into the request the app sends to `topo monitor stream`.
/// Each section is a row set in the template; what any of it means is
/// decided by `topo`.
public struct TemplateCompiler: Sendable {
    /// Row IDs, fixed so frames can be read back by section.
    public enum RowID {
        public static let status = "status"
        public static let seen = "seen"
        public static let attention = "attention"
        public static let applications = "apps"
        public static let mac = "mac"
        public static func server(_ index: Int) -> String { "server-\(index + 1)" }
        public static func extra(_ index: Int) -> String { "widget-server-\(index + 1)" }
    }

    /// What widgets on the desktop need beyond the panel's own sections.
    public struct WidgetNeeds: Sendable, Hashable {
        /// Seen from, Needs attention and Applications, for the larger sizes.
        public var lists: Bool
        /// Nodes shown by Server widgets.
        public var nodes: [String]

        public init(lists: Bool = false, nodes: [String] = []) {
            self.lists = lists
            self.nodes = nodes
        }

        public static let none = WidgetNeeds()
    }

    public var title = "Topophany"

    public init() {}

    public func request(for settings: Settings, revision: Int, widgets: WidgetNeeds = .none, lang: String? = nil) -> Request {
        let s = settings.sections
        var rows = [TemplateRow(id: RowID.status, metric: "summary.verdict", visual: "status")]
        for id in s.order {
            switch id {
            case .status:
                break
            case .seen where s.seen || widgets.lists:
                rows.append(TemplateRow(id: RowID.seen, metric: "observers.verdicts", visual: "list"))
            case .attention where s.attention || widgets.lists:
                let limit = max(s.attention ? s.attentionLimit : 3, widgets.lists ? 3 : 1)
                rows.append(TemplateRow(id: RowID.attention, metric: "attention.list", visual: "list", limit: min(20, limit)))
            case .applications where s.applications || widgets.lists:
                rows.append(TemplateRow(id: RowID.applications, metric: "applications.list", visual: "list"))
            case .servers where s.servers || widgets.lists:
                for (i, node) in Self.unique(s.serverNodes).enumerated() {
                    rows.append(Self.card(RowID.server(i), node))
                }
            case .mac where s.mac.mode == .server && Self.validNode(s.mac.node):
                rows.append(Self.card(RowID.mac, s.mac.node))
            default:
                break
            }
        }
        let requested = Set(rows.compactMap(\.select?.node))
        for (i, node) in Self.unique(widgets.nodes).filter({ !requested.contains($0) }).enumerated() {
            rows.append(Self.card(RowID.extra(i), node))
        }
        let t = settings.topo
        let preview = t.source == "preview"
        return Request(
            requestID: "settings-\(revision)",
            source: preview ? "preview" : "client",
            profile: preview ? "" : t.profile,
            observer: t.observer,
            scenario: preview ? (t.scenario ?? 0) : nil,
            lang: preview ? lang : nil,
            interval: (Interval(t.interval) ?? Interval(seconds: 5)).clampedToRefresh.description,
            template: Template(title: title, bar: .init(row: RowID.status), rows: rows))
    }

    static func card(_ id: String, _ node: String) -> TemplateRow {
        TemplateRow(id: id, metric: "server.card", visual: "card", select: .init(node: node))
    }

    static func unique(_ nodes: [String]) -> [String] {
        var seen = Set<String>()
        return nodes.filter { validNode($0) && seen.insert($0).inserted }
    }

    /// A topology ID, as `config.ID` accepts one.
    public static func validNode(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, s.utf8.count <= 96 else { return false }
        func alnum(_ c: Unicode.Scalar) -> Bool { c.isASCII && (CharacterSet.alphanumerics.contains(c)) }
        guard alnum(first) else { return false }
        return s.unicodeScalars.allSatisfy { alnum($0) || $0 == "_" || $0 == "." || $0 == "-" }
    }
}
