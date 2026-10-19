import Foundation

/// What the user chooses to look at, and how it looks; never what it means
/// (DESIGN.md §9). Stored as `settings.json`. Missing fields take their
/// defaults and unknown ones are ignored.
public struct Settings: Sendable, Hashable, Codable {
    public var schema: Int = 1
    public var topo = Topo()
    public var appearance = Appearance()
    public var sections = Sections()
    public var openAtLogin = true
    /// The bundle identifier of the terminal that opens the TUI; empty for
    /// the system's terminal for scripts.
    public var terminal = ""
    /// The language of the panel, the menu bar item, widgets and Settings.
    public var language: Language = .system

    public enum Language: String, Sendable, Hashable, Codable, CaseIterable {
        case system, en, ja, zhHans = "zh-Hans"

        /// The localization to use, or `nil` to follow the system's
        /// languages.
        public var localization: String? { self == .system ? nil : rawValue }
    }

    public init() {}

    enum CodingKeys: String, CodingKey { case schema, topo, appearance, sections, openAtLogin, terminal, language }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        schema = (try? c.decodeIfPresent(Int.self, forKey: .schema)) ?? 1
        topo = (try? c.decodeIfPresent(Topo.self, forKey: .topo)) ?? d.topo
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
        sections = (try? c.decodeIfPresent(Sections.self, forKey: .sections)) ?? d.sections
        openAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .openAtLogin)) ?? d.openAtLogin
        terminal = (try? c.decodeIfPresent(String.self, forKey: .terminal)) ?? d.terminal
        language = c.text(.language).flatMap(Language.init(rawValue:)) ?? d.language
    }

    // MARK: topo

    public struct Topo: Sendable, Hashable, Codable {
        /// The `topo` executable; empty to search for it.
        public var path = ""
        /// A saved profile; empty for the active one.
        public var profile = ""
        /// The observer to view from; empty for all observers.
        public var observer = ""
        /// How often `topo` refreshes the display, 1 s to 1 h.
        public var interval = "5s"
        /// `client` reads the collector; `preview` reads `topo preview`'s
        /// synthetic network.
        public var source = "client"
        /// `preview` only.
        public var scenario: Int?

        public init() {}

        enum CodingKeys: String, CodingKey { case path, profile, observer, interval, source, scenario }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = c.text(.path) ?? ""
            profile = c.text(.profile) ?? ""
            observer = c.text(.observer) ?? ""
            interval = c.text(.interval).flatMap { Interval($0) }.map { $0.clampedToRefresh.description } ?? "5s"
            source = c.text(.source) == "preview" ? "preview" : "client"
            scenario = c.count(.scenario)
        }
    }

    // MARK: appearance

    public struct Appearance: Sendable, Hashable, Codable {
        public enum Panel: String, Sendable, Hashable, Codable, CaseIterable { case system, light, dark }
        public enum TextSize: String, Sendable, Hashable, Codable, CaseIterable { case small, `default`, large }
        public enum Show: String, Sendable, Hashable, Codable, CaseIterable { case symbol, count, words }

        public struct MenuBar: Sendable, Hashable, Codable {
            public var show: Show = .count
            public var statusColors = true
            /// The item moves: it turns while what it shows is current, and
            /// its changes animate. Reduce Motion keeps it still regardless.
            public var motion = true

            public init() {}

            enum CodingKeys: String, CodingKey { case show, statusColors, motion }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                show = c.text(.show).flatMap(Show.init(rawValue:)) ?? .count
                statusColors = (try? c.decodeIfPresent(Bool.self, forKey: .statusColors)) ?? true
                motion = (try? c.decodeIfPresent(Bool.self, forKey: .motion)) ?? true
            }
        }

        /// A theme ID: `native` or `terminal`.
        public var theme = "native"
        public var panel: Panel = .system
        public var textSize: TextSize = .default
        public var menuBar = MenuBar()

        public init() {}

        enum CodingKeys: String, CodingKey { case theme, panel, textSize, menuBar }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            theme = c.text(.theme) ?? "native"
            panel = c.text(.panel).flatMap(Panel.init(rawValue:)) ?? .system
            textSize = c.text(.textSize).flatMap(TextSize.init(rawValue:)) ?? .default
            menuBar = (try? c.decodeIfPresent(MenuBar.self, forKey: .menuBar)) ?? MenuBar()
        }
    }
}

// MARK: sections

public enum SectionID: String, Sendable, Hashable, Codable, CaseIterable {
    case status, seen, attention, applications, fleet, servers, zones, mac
}

/// The panel's sections: their order, and each one's choices. Status is
/// always first. Stored as an ordered array of objects, as DESIGN.md §9
/// shows.
public struct Sections: Sendable, Hashable, Codable {
    public static let defaultOrder: [SectionID] = [.status, .seen, .attention, .applications, .fleet, .servers, .zones, .mac]

    public enum MacMode: String, Sendable, Hashable, Codable, CaseIterable { case local, server, off }
    public enum Reading: String, Sendable, Hashable, Codable, CaseIterable { case cpu, memory, storage, network, battery }

    public struct Mac: Sendable, Hashable {
        public var mode: MacMode = .local
        public var readings: [Reading] = Reading.allCases
        public var every = "2s"
        /// As a server: the node to show.
        public var node = ""
        /// Local readings: the volume to measure; empty for the startup disk.
        public var volume = ""
        /// Local readings: the interface; empty for the primary one.
        public var interface = ""
        /// As a server: which parts of the card to show.
        public var resources = true
        public var services = true
        public var observes = true

        public init() {}
    }

    /// Sections in panel order, Status first.
    public var order: [SectionID] = Sections.defaultOrder
    /// Keep Status pinned while the rest scrolls beneath it.
    public var pinStatus = true
    public var seen = true
    public var attention = true
    /// 3 or 5 rows.
    public var attentionLimit = 3
    public var applications = true
    /// Applications to show by ID; empty for all.
    public var applicationsOnly: [String] = []
    /// Fleet: every node `topo` lists, by who runs it.
    public var fleet = true
    public var servers = false
    /// Pinned servers by node ID.
    public var serverNodes: [String] = []
    /// Time zones: listed servers by the time zone of their place.
    public var zones = true
    /// A place (as `topo` names it) → the time zone chosen for it, an IANA
    /// identifier, or "" for none. Places not here take the zone their name
    /// suggests.
    public var placeZones: [String: String] = [:]
    public var mac = Mac()

    public init() {}

    public func isEnabled(_ id: SectionID) -> Bool {
        switch id {
        case .status: true
        case .seen: seen
        case .attention: attention
        case .applications: applications
        case .fleet: fleet
        case .servers: servers
        case .zones: zones
        case .mac: mac.mode != .off
        }
    }

    public mutating func setEnabled(_ id: SectionID, _ on: Bool) {
        switch id {
        case .status: break
        case .seen: seen = on
        case .attention: attention = on
        case .applications: applications = on
        case .fleet: fleet = on
        case .servers: servers = on
        case .zones: zones = on
        case .mac: if !on { mac.mode = .off } else if mac.mode == .off { mac.mode = .local }
        }
    }

    /// Moves a section; Status stays first.
    public mutating func move(_ id: SectionID, to index: Int) {
        guard id != .status, let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: max(1, min(index, order.count)))
    }

    private struct Entry: Codable {
        var id: String
        var pinned: Bool?
        var enabled: Bool?
        var limit: Int?
        var only: [String]?
        var nodes: [String]?
        var places: [String: String]?
        var mode: String?
        var readings: [String]?
        var every: String?
        var node: String?
        var volume: String?
        var interface: String?
        var resources: Bool?
        var services: Bool?
        var observes: Bool?
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var seenOrder: [SectionID] = []
        while !c.isAtEnd {
            guard let e = try? c.decode(Entry.self) else {
                _ = try? c.decode(JSONValue.self)
                continue
            }
            guard let id = SectionID(rawValue: e.id), !seenOrder.contains(id) else { continue }
            seenOrder.append(id)
            switch id {
            case .status: pinStatus = e.pinned ?? true
            case .seen: seen = e.enabled ?? true
            case .attention:
                attention = e.enabled ?? true
                attentionLimit = e.limit.map { $0 >= 5 ? 5 : 3 } ?? 3
            case .applications:
                applications = e.enabled ?? true
                applicationsOnly = e.only ?? []
            case .fleet: fleet = e.enabled ?? true
            case .servers:
                servers = e.enabled ?? false
                serverNodes = e.nodes ?? []
            case .zones:
                zones = e.enabled ?? true
                placeZones = e.places ?? [:]
            case .mac:
                mac.mode = e.mode.flatMap(MacMode.init(rawValue:)) ?? (e.enabled == false ? .off : .local)
                if let r = e.readings { mac.readings = r.compactMap(Reading.init(rawValue:)) }
                mac.every = e.every.flatMap { Interval($0) }.map { Interval(seconds: min(60, max(1, $0.seconds.rounded()))).description } ?? "2s"
                mac.node = e.node ?? ""
                mac.volume = e.volume ?? ""
                mac.interface = e.interface ?? ""
                mac.resources = e.resources ?? true
                mac.services = e.services ?? true
                mac.observes = e.observes ?? true
            }
        }
        var o = [SectionID.status] + seenOrder.filter { $0 != .status }
        // A section the file doesn't list, such as one added since it was
        // written, goes after the section that precedes it by default.
        for (i, id) in Self.defaultOrder.enumerated() where !o.contains(id) {
            let previous = Self.defaultOrder[..<i].last { o.contains($0) }
            o.insert(id, at: previous.flatMap { o.firstIndex(of: $0) }.map { $0 + 1 } ?? o.count)
        }
        order = o
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for id in order {
            var e = Entry(id: id.rawValue)
            switch id {
            case .status: e.pinned = pinStatus
            case .seen: e.enabled = seen
            case .attention:
                e.enabled = attention
                e.limit = attentionLimit
            case .applications:
                e.enabled = applications
                e.only = applicationsOnly
            case .fleet: e.enabled = fleet
            case .servers:
                e.enabled = servers
                e.nodes = serverNodes
            case .zones:
                e.enabled = zones
                e.places = placeZones
            case .mac:
                e.mode = mac.mode.rawValue
                e.readings = mac.readings.map(\.rawValue)
                e.every = mac.every
                e.node = mac.node
                e.volume = mac.volume
                e.interface = mac.interface
                e.resources = mac.resources
                e.services = mac.services
                e.observes = mac.observes
            }
            try c.encode(e)
        }
    }
}
