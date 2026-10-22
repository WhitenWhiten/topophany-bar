import Foundation
import TopophanyKit
import TopophanySections
import TopophanyThemes

/// What the app leaves for its widgets in the App Group container: the
/// latest frame as `topo` wrote it, what the reader knew, the theme and the
/// user's choices. A widget can't read the stream; this is all it gets.
public struct Handoff: Sendable, Codable {
    public var schema = 1
    /// When the app wrote it. Widgets read the frame as of this moment and
    /// trust their timeline, not the 30 s lease, after it.
    public var writtenAt: Date
    /// When the app will renew it at the latest.
    public var heartbeat: TimeInterval
    /// The last running frame's line, or nil before the first.
    public var frame: Data?
    public var receivedAt: Date?
    public var lastKnown: LastKnown?
    /// Whether the engine was producing frames when this was written.
    public var engineRunning: Bool
    public var theme: Data
    public var settings: Data

    public init(writtenAt: Date, heartbeat: TimeInterval, frame: Data?, receivedAt: Date?, lastKnown: LastKnown?,
                engineRunning: Bool, theme: Data, settings: Data) {
        self.writtenAt = writtenAt
        self.heartbeat = heartbeat
        self.frame = frame
        self.receivedAt = receivedAt
        self.lastKnown = lastKnown
        self.engineRunning = engineRunning
        self.theme = theme
        self.settings = settings
    }

    /// From what the app's reader holds.
    public init(policy: ReaderPolicy, theme: Theme, settings: TopophanyKit.Settings, engineRunning: Bool,
                at now: Date, heartbeat: TimeInterval = WidgetSchedule.heartbeat) {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        self.init(writtenAt: now, heartbeat: heartbeat, frame: policy.line, receivedAt: policy.receivedAt,
                  lastKnown: policy.lastKnown, engineRunning: engineRunning,
                  theme: (try? e.encode(theme)) ?? Data(), settings: (try? e.encode(settings)) ?? Data())
    }

    public var decodedTheme: Theme {
        (try? JSONDecoder().decode(Theme.self, from: theme)) ?? ThemeStore.native
    }

    public var decodedSettings: TopophanyKit.Settings {
        (try? JSONDecoder().decode(TopophanyKit.Settings.self, from: settings)) ?? TopophanyKit.Settings()
    }

    /// What the reader showed when this was written.
    public var decodedFrame: Frame? { frame.flatMap(FrameDecoder.frame(from:)) }
    public var isDirect: Bool { decodedFrame?.source == "direct" || decodedSettings.topo.source == "direct" }
    public var datasetScope: String { (decodedFrame?.source ?? decodedSettings.topo.source) + ":" + (decodedFrame?.datasetID ?? "") }

    /// Direct node choices carry dataset identity. Unscoped old choices cannot silently rebind.
    public func selectionID(node: String) -> String {
        guard isDirect else { return node }
        return "direct/" + Data(datasetScope.utf8).base64EncodedString() + "/" + node
    }
    public func resolveSelection(_ id: String) -> String? {
        if isDirect {
            let prefix = "direct/" + Data(datasetScope.utf8).base64EncodedString() + "/"
            guard id.hasPrefix(prefix) else { return nil }
            return String(id.dropFirst(prefix.count))
        }
        return id.hasPrefix("direct/") ? nil : id
    }

    public func reading(at date: Date? = nil) -> Reading {
        var f = decodedFrame
        let evaluatedAt = date ?? writtenAt
        // Direct is explicitly a resource snapshot, bounded by its original row/resource deadlines.
        // A snapshot does not claim that a publisher is still alive.
        if isDirect, date != nil { f?.publisherExpiresAt = evaluatedAt.addingTimeInterval(30) }
        var p = ReaderPolicy(frame: f, line: frame, receivedAt: receivedAt, lastKnown: lastKnown,
                             source: engineRunning ? .open : .ended(at: writtenAt))
        if f == nil, !engineRunning { p.sourceEnded(at: writtenAt) }
        return p.evaluate(at: evaluatedAt)
    }

    /// The panel's section models as they were when this was written.
    public func panel() -> PanelModel { panel(at: nil) }
    public func panel(at date: Date?) -> PanelModel {
        var p = panel(reading: reading(at: date), settings: decodedSettings)
        if var source = p.status.sources { source.snapshotAt = decodedFrame?.generatedAt; p.status.sources = source }
        return p
    }

    private func panel(reading: Reading, settings s: TopophanyKit.Settings) -> PanelModel {
        var widgetSettings = s
        // Widgets draw every list section, whatever the panel shows.
        widgetSettings.sections.seen = true
        widgetSettings.sections.attention = true
        widgetSettings.sections.attentionLimit = max(3, s.sections.attentionLimit)
        widgetSettings.sections.applications = true
        widgetSettings.sections.fleet = true
        widgetSettings.sections.servers = true
        widgetSettings.sections.services = true
        widgetSettings.sections.map = true
        // Widgets draw neither Time zones nor local readings.
        widgetSettings.sections.zones = false
        if widgetSettings.sections.mac.mode == .local { widgetSettings.sections.mac.mode = .off }
        return SectionBuilder.panel(PanelInput(reading: reading, engine: engineRunning ? .running : .stopped,
                                               settings: widgetSettings))
    }

    /// The panel for a Time zones widget: the zones as the clocks read at
    /// `date`, the marks as they were when this was written.
    public func panel(zonesAt date: Date, here: TimeZone = .autoupdatingCurrent) -> PanelModel {
        zonesPanelBuilder(here: here)(date)
    }

    /// Decode once per timeline. Only the clocks change between entries;
    /// health remains the evidence held when the hand-off was written.
    func zonesPanelBuilder(here: TimeZone) -> (Date) -> PanelModel {
        let r = reading()
        let s = decodedSettings
        var minimal = s
        minimal.sections.order = []
        let base = SectionBuilder.panel(PanelInput(reading: r, engine: engineRunning ? .running : .stopped, settings: minimal))
        return { date in
            var p = base
            p.sections = [.zones(SectionBuilder.zones(r, chosen: s.sections.placeZones, pinned: s.sections.serverNodes,
                                                     here: here, at: date))]
            return p
        }
    }

    /// The servers `topo` last listed, for choosing a Server widget's node.
    public func servers() -> [ServerListEntry] {
        let r = reading()
        guard let row = r.row(TemplateCompiler.RowID.servers), case .servers(let list) = r.lastValue(of: row) else { return [] }
        return list
    }

    /// The services `topo` last listed, for choosing a Service widget's.
    public func services() -> [ServiceListEntry] {
        let r = reading()
        guard let row = r.row(TemplateCompiler.RowID.services), case .services(let list) = r.lastValue(of: row) else { return [] }
        return list
    }

    /// The panel for a Service widget: its service's card is the one
    /// service, whether or not the panel pins it.
    public func panel(service id: String) -> PanelModel {
        let r = reading()
        var p = panel(reading: r, settings: decodedSettings)
        let cards = SectionBuilder.services(r, ids: [id])
        p.sections.removeAll { if case .services = $0 { true } else { false } }
        p.sections.append(.services(cards))
        return p
    }

    /// The panel for a Server widget: its node's card is the one server,
    /// whether or not the panel pins it.
    public func panel(server node: String, at date: Date? = nil) -> PanelModel {
        let r = reading(at: date)
        var p = panel(at: date)
        if case .server(let c, _)? = p.mac, c.id == node { return p }
        let cards = SectionBuilder.servers(r, nodes: [node])
        p.sections.removeAll { if case .servers = $0 { true } else { false } }
        p.sections.append(.servers(cards))
        return p
    }
}

/// Reads and writes the hand-off in the App Group container.
public struct HandoffStore: Sendable {
    public let directory: URL?

    /// The App Group's container, or nil when this build has no App Group
    /// (an unsigned debug build): widgets then get nothing.
    public init(appGroup: String?) {
        directory = appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    public init(directory: URL?) { self.directory = directory }

    /// The App Group named in the bundle's Info.plist (`TopophanyAppGroup`).
    public static var bundleAppGroup: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "TopophanyAppGroup") as? String,
              !g.isEmpty, !g.hasPrefix("$(") else { return nil }
        return g
    }

    var url: URL? { directory?.appending(path: "handoff.json") }

    public var isAvailable: Bool { directory != nil }

    public func write(_ h: Handoff) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(h).write(to: url, options: .atomic)
    }

    public func read() -> Handoff? {
        guard let url, let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Handoff.self, from: d)
    }
}
