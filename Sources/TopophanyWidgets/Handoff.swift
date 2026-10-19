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
    public func reading() -> Reading {
        let f = frame.flatMap(FrameDecoder.frame(from:))
        var p = ReaderPolicy(frame: f, line: frame, receivedAt: receivedAt, lastKnown: lastKnown,
                             source: engineRunning ? .open : .ended(at: writtenAt))
        if f == nil, !engineRunning { p.sourceEnded(at: writtenAt) }
        return p.evaluate(at: writtenAt)
    }

    /// The panel's section models as they were when this was written.
    public func panel() -> PanelModel {
        let s = decodedSettings
        var widgetSettings = s
        // Widgets draw every list section, whatever the panel shows.
        widgetSettings.sections.seen = true
        widgetSettings.sections.attention = true
        widgetSettings.sections.attentionLimit = max(3, s.sections.attentionLimit)
        widgetSettings.sections.applications = true
        widgetSettings.sections.fleet = true
        widgetSettings.sections.servers = true
        // Widgets draw neither Time zones nor local readings.
        widgetSettings.sections.zones = false
        if widgetSettings.sections.mac.mode == .local { widgetSettings.sections.mac.mode = .off }
        return SectionBuilder.panel(PanelInput(reading: reading(), engine: engineRunning ? .running : .stopped,
                                               settings: widgetSettings))
    }

    /// The servers `topo` last listed, for choosing a Server widget's node.
    public func servers() -> [ServerListEntry] {
        let r = reading()
        guard let row = r.row(TemplateCompiler.RowID.servers), case .servers(let list) = r.lastValue(of: row) else { return [] }
        return list
    }

    /// The panel for a Server widget: its node's card is the one server,
    /// whether or not the panel pins it.
    public func panel(server node: String) -> PanelModel {
        var p = panel()
        if case .server(let c, _)? = p.mac, c.id == node { return p }
        let cards = SectionBuilder.servers(reading(), nodes: [node])
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
