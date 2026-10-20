import Foundation
import TopophanyKit

/// What the widgets on the desktop show, as the extension last saw them.
/// The extension records each widget it draws; the app reads the record and
/// asks `topo` for the rows they need beyond the panel's own.
public struct WidgetNeedsStore: Sendable {
    public struct Entry: Sendable, Hashable, Codable {
        /// Large and extra large Status widgets draw the lists.
        public var lists: Bool
        /// A Server widget's node.
        public var node: String?
        /// A Service widget's service.
        public var service: String?
        /// A Time zones widget, which draws every listed server's mark.
        public var zones: Bool?
        public var at: Date

        public init(lists: Bool, node: String?, service: String? = nil, zones: Bool = false, at: Date) {
            self.lists = lists
            self.node = node
            self.service = service
            self.zones = zones ? true : nil
            self.at = at
        }
    }

    /// A widget that hasn't been drawn for this long has been removed: every
    /// widget on the desktop is drawn at least once a heartbeat.
    public static let forgetAfter: TimeInterval = 2 * WidgetSchedule.heartbeat + WidgetSchedule.grace

    public let directory: URL?

    public init(directory: URL?) { self.directory = directory }

    public init(appGroup: String?) { self.init(directory: HandoffStore(appGroup: appGroup).directory) }

    var url: URL? { directory?.appending(path: "widget-needs.json") }

    public func entries() -> [String: Entry] {
        guard let url, let d = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: d)) ?? [:]
    }

    /// Records one widget, by a key that names its kind, size and choices.
    public func record(_ key: String, _ entry: Entry) {
        guard let url else { return }
        var all = entries().filter { entry.at.timeIntervalSince($0.value.at) < Self.forgetAfter }
        guard all[key].map({ $0.lists != entry.lists || $0.node != entry.node || $0.service != entry.service || $0.zones != entry.zones
            || entry.at.timeIntervalSince($0.at) > 60 }) ?? true
        else { return }
        all[key] = entry
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: url, options: .atomic)
    }

    /// What the app's request must carry for the widgets drawn lately.
    public func needs(at now: Date = Date()) -> TemplateCompiler.WidgetNeeds {
        let live = entries().values.filter { now.timeIntervalSince($0.at) < Self.forgetAfter }
        let nodes = Set(live.compactMap(\.node)).sorted()
        let services = Set(live.compactMap(\.service)).sorted()
        return TemplateCompiler.WidgetNeeds(lists: live.contains { $0.lists }, nodes: nodes, services: services)
    }

    /// A Time zones widget was drawn lately.
    public func zones(at now: Date = Date()) -> Bool {
        entries().values.contains { now.timeIntervalSince($0.at) < Self.forgetAfter && $0.zones == true }
    }
}
