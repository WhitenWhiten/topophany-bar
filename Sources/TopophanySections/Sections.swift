import Foundation
import LocalReadings
import TopophanyKit

/// Seen from: observers that see a problem, worst first as `topo` ordered
/// them, then how many report none. "Is it me or them?"
public struct SeenFromSection: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var mark: Mark
        /// "3 down", "1 warn", "silent 3m".
        public var note: String

        public init(id: String, name: String, mark: Mark, note: String) {
            self.id = id
            self.name = name
            self.mark = mark
            self.note = note
        }
    }

    /// `nil` while nothing current is known.
    public var problems: [Entry]?
    /// Observers that report no problem.
    public var calm: Int
    /// How many observers there are, or nil when that was never known.
    public var total: Int?

    public init(problems: [Entry]?, calm: Int, total: Int?) {
        self.problems = problems
        self.calm = calm
        self.total = total
    }

    public var isKnown: Bool { problems != nil }
}

/// Needs attention: open incidents first, then the rest in `topo`'s order.
public struct AttentionSection: Sendable, Hashable {
    public struct Item: Sendable, Hashable, Identifiable {
        public var id: String
        public var kind: String
        /// The title split at its arrows, without the observer.
        public var route: [String]
        public var mark: Mark
        public var pill: Pill
        public var observer: String
        public var observerName: String
        public var since: Date?

        public init(id: String, kind: String, route: [String], mark: Mark, pill: Pill, observer: String,
                    observerName: String, since: Date?) {
            self.id = id
            self.kind = kind
            self.route = route
            self.mark = mark
            self.pill = pill
            self.observer = observer
            self.observerName = observerName
            self.since = since
        }

        public var title: String { route.joined(separator: " → ") }
    }

    public var items: [Item]
    /// The whole list, of which `items` is the start.
    public var total: Int
    public var now: Date

    public init(items: [Item], total: Int, now: Date) {
        self.items = items
        self.total = total
        self.now = now
    }

    /// Entries beyond those shown: "14 more in Topophany".
    public var more: Int { max(0, total - items.count) }
}

/// One row per declared application.
public struct ApplicationsSection: Sendable, Hashable {
    public struct Row: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var mark: Mark
        /// One mark per service, in topology order.
        public var services: [Mark]
        public var note: String
        /// Whether the note asks for a look ("3 attention").
        public var noteNeedsLook: Bool

        public init(id: String, name: String, mark: Mark, services: [Mark], note: String, noteNeedsLook: Bool) {
            self.id = id
            self.name = name
            self.mark = mark
            self.services = services
            self.note = note
            self.noteNeedsLook = noteNeedsLook
        }
    }

    public var rows: [Row]
    /// Shown from the last frame with every health withheld.
    public var isCurrent: Bool

    public init(rows: [Row], isCurrent: Bool) {
        self.rows = rows
        self.isCurrent = isCurrent
    }

    public var serviceCount: Int { rows.reduce(0) { $0 + $1.services.count } }

    /// The rows that fit in `lines`, in order, and those left out for a
    /// last line that counts them: all of them when they fit.
    public func cut(_ lines: Int) -> (shown: [Row], rest: [Row]) {
        guard rows.count > lines else { return (rows, []) }
        let n = max(0, lines - 1)
        return (Array(rows.prefix(n)), Array(rows.dropFirst(n)))
    }
}

/// A server's card, as the Servers tab draws it.
public struct ServerCardModel: Sendable, Hashable, Identifiable {
    public struct Meter: Sendable, Hashable {
        /// `nil` when unknown: drawn hatched, never as zero.
        public var percent: Double?
        /// The check's own limit; `nil` when it sets none.
        public var limit: Double?
        /// "8 CPUs", "7.4 / 16 GiB".
        public var detail: String

        public init(percent: Double?, limit: Double?, detail: String) {
            self.percent = percent
            self.limit = limit
            self.detail = detail
        }

        /// Past the check's own limit, as the TUI marks it.
        public var isOverLimit: Bool {
            guard let p = percent, let l = limit, l > 0 else { return false }
            return p > l
        }
    }

    public struct Service: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var mark: Mark
        /// "affected", "not monitored" or empty.
        public var note: String

        public init(id: String, name: String, mark: Mark, note: String) {
            self.id = id
            self.name = name
            self.mark = mark
            self.note = note
        }
    }

    public struct Observes: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var mark: Mark
        /// "9 checks · all pass".
        public var text: String

        public init(id: String, name: String, mark: Mark, text: String) {
            self.id = id
            self.name = name
            self.mark = mark
            self.text = text
        }
    }

    public var id: String
    public var name: String
    public var kind: String
    public var provider: String
    public var place: String
    public var mark: Mark
    public var pill: Pill
    /// Past its deadline, or nothing current: values withheld.
    public var isWithheld: Bool
    /// The node isn't in the topology.
    public var isMissing: Bool
    public var cpu: Meter
    public var memory: Meter
    public var disk: Meter
    public var services: [Service]
    /// "4 services · 3 up · 1 not monitored".
    public var servicesSummary: String
    public var observes: [Observes]
    /// When the readings were sampled.
    public var sampledAt: Date?
    public var now: Date
    /// Its place's time zone, for the time where it is.
    public var timeZone: TimeZone?

    public init(id: String, name: String, kind: String, provider: String, place: String, mark: Mark, pill: Pill,
                isWithheld: Bool, isMissing: Bool = false, cpu: Meter, memory: Meter, disk: Meter, services: [Service],
                servicesSummary: String, observes: [Observes], sampledAt: Date?, now: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.provider = provider
        self.place = place
        self.mark = mark
        self.pill = pill
        self.isWithheld = isWithheld
        self.isMissing = isMissing
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.services = services
        self.servicesSummary = servicesSummary
        self.observes = observes
        self.sampledAt = sampledAt
        self.now = now
    }

    /// "host · Oracle · New York", the kind in the panel's language.
    public var subtitle: String { Words.join([Words.kind(kind), provider, place]) }

    /// The time where it is, "5:17 AM", when its place has a time zone.
    public var localTime: String? {
        timeZone.map { z in
            let t = Words.time(now, in: z)
            return Words.clock(t.time, t.period)
        }
    }

    /// "4s ago", or "last reading 3 min ago" when withheld.
    public var age: String {
        guard let sampledAt else { return isMissing ? "" : tr("no reading") }
        let a = Words.ago(sampledAt, now: now)
        return isWithheld ? tr("last reading \(a)") : a
    }
}

/// This Mac: its own readings, or its server card.
public enum MacSection: Sendable, Hashable {
    case local(LocalSection)
    case server(ServerCardModel, node: String)
}

/// This Mac's local readings. They carry no health: they are not evidence.
public struct LocalSection: Sendable, Hashable {
    public var model: String
    public var readings: [Sections.Reading]
    public var snapshot: LocalSnapshot?

    public init(model: String, readings: [Sections.Reading], snapshot: LocalSnapshot?) {
        self.model = model
        self.readings = readings
        self.snapshot = snapshot
    }

    public func shows(_ r: Sections.Reading) -> Bool { readings.contains(r) }

    public var cpu: CPUReading? { shows(.cpu) ? snapshot?.latest.cpu : nil }
    public var memory: MemoryReading? { shows(.memory) ? snapshot?.latest.memory : nil }
    public var storage: StorageReading? { shows(.storage) ? snapshot?.latest.storage : nil }
    public var network: NetworkReading? { shows(.network) ? snapshot?.latest.network : nil }
    public var battery: BatteryReading? { shows(.battery) ? snapshot?.latest.battery : nil }
    public var cpuHistory: [Double] { snapshot?.cpuHistory ?? [] }
    public var receivedHistory: [Double] { snapshot?.receivedHistory ?? [] }
    public var sentHistory: [Double] { snapshot?.sentHistory ?? [] }

    public var batteryState: String {
        guard let b = battery else { return "" }
        switch b.state {
        case .charging: return tr("Charging")
        case .charged: return tr("Charged")
        case .discharging: return tr("On battery")
        case .onPower: return tr("On power")
        }
    }

    public var batteryRemaining: String {
        guard let b = battery, let m = b.minutesRemaining else { return "" }
        let t = Words.clock(minutes: m)
        return b.state == .charging ? tr("\(t) to full") : tr("\(t) remaining")
    }
}

/// The panel's header and footer.
public struct PanelChrome: Sendable, Hashable {
    public enum Connection: Sendable, Hashable {
        case connected
        case unreachable
        case starting
        case restarting(at: Date?)
        case notRunning(String)
    }

    /// The project the frame is from, "homelab".
    public var project: String
    /// "all observers", or the observer viewed from.
    public var view: String
    public var connection: Connection
    public var updatedAt: Date?
    public var now: Date

    public init(project: String, view: String, connection: Connection, updatedAt: Date?, now: Date) {
        self.project = project
        self.view = view
        self.connection = connection
        self.updatedAt = updatedAt
        self.now = now
    }

    public var isLive: Bool { connection == .connected }

    /// "Connected · homelab".
    public var connectionText: String {
        let p = project.isEmpty ? tr("collector") : project
        switch connection {
        case .connected: return tr("Connected · \(p)")
        case .unreachable: return tr("Unreachable · \(p)")
        case .starting: return tr("Starting topo…")
        case .restarting(let at?):
            let s = max(1, Int(at.timeIntervalSince(now).rounded(.up)))
            return tr("Restarting topo in \(s) s")
        case .restarting(nil): return tr("Restarting topo…")
        case .notRunning(let why): return why
        }
    }
}

/// Everything the panel shows, in order.
public struct PanelModel: Sendable, Hashable {
    public enum Section: Sendable, Hashable, Identifiable {
        case seen(SeenFromSection)
        case attention(AttentionSection)
        case applications(ApplicationsSection)
        case fleet(FleetSection)
        case servers([ServerCardModel])
        case zones(ZonesSection)
        case mac(MacSection)

        public var id: SectionID {
            switch self {
            case .seen: .seen
            case .attention: .attention
            case .applications: .applications
            case .fleet: .fleet
            case .servers: .servers
            case .zones: .zones
            case .mac: .mac
            }
        }
    }

    public var chrome: PanelChrome
    public var status: StatusSection
    public var sections: [Section]
    /// Keep Status pinned while the rest scrolls.
    public var pinStatus: Bool
    /// Whether the menu bar's alert can be quieted, or shown again.
    public var alert: MenuBarAlert
    /// While no `topo` can run, the offer to download one.
    public var download: TopoOffer?

    public init(chrome: PanelChrome, status: StatusSection, sections: [Section], pinStatus: Bool = true,
                alert: MenuBarAlert = .unavailable, download: TopoOffer? = nil) {
        self.chrome = chrome
        self.status = status
        self.sections = sections
        self.pinStatus = pinStatus
        self.alert = alert
        self.download = download
    }

    public func section(_ id: SectionID) -> Section? { sections.first { $0.id == id } }

    public var seen: SeenFromSection? { if case .seen(let s)? = section(.seen) { s } else { nil } }
    public var attention: AttentionSection? { if case .attention(let s)? = section(.attention) { s } else { nil } }
    public var applications: ApplicationsSection? { if case .applications(let s)? = section(.applications) { s } else { nil } }
    public var fleet: FleetSection? { if case .fleet(let s)? = section(.fleet) { s } else { nil } }
    public var servers: [ServerCardModel] { if case .servers(let s)? = section(.servers) { s } else { [] } }
    public var zones: ZonesSection? { if case .zones(let s)? = section(.zones) { s } else { nil } }
    public var mac: MacSection? { if case .mac(let s)? = section(.mac) { s } else { nil } }
}

// MARK: the shortest panel

extension PanelModel {
    /// The panel at its shortest: its own header, Status and footer, with
    /// This Mac's four readings and two time zones between (DESIGN.md §4).
    /// Laid out, it says how short the panel may be made. It is never
    /// shown, so its readings, places and clocks only stand in.
    public var shortest: PanelModel {
        let now = chrome.now
        let gb: UInt64 = 1 << 30
        let sample = LocalSample(
            at: now, cpu: CPUReading(total: 12, system: 4, user: 8, logicalCores: 8),
            memory: MemoryReading(totalBytes: 16 * gb, appBytes: 6 * gb, wiredBytes: 2 * gb, compressedBytes: gb, usedBytes: 9 * gb,
                                  usedPercent: 56, pressurePercent: 30),
            storage: StorageReading(volumeName: "Macintosh HD", path: "/", totalBytes: Int64(512 * gb), availableBytes: Int64(256 * gb),
                                    usedBytes: Int64(256 * gb), usedPercent: 50),
            network: NetworkReading(interface: "en0", displayName: "Wi-Fi", address: "192.168.1.2", receivedPerSecond: 120_000,
                                    sentPerSecond: 40_000))
        let history = Array(repeating: 20.0, count: LocalSnapshot.historyLength)
        let local = LocalSnapshot(machine: MachineInfo(model: "Mac", chip: "", hasBattery: false), latest: sample,
                                  cpuHistory: history, receivedHistory: history, sentHistory: history)
        let here = TimeZone.current
        let away = TimeZone(identifier: here.identifier == "Asia/Tokyo" ? "Europe/London" : "Asia/Tokyo") ?? .gmt
        func zone(_ tz: TimeZone, _ place: String, isHere: Bool) -> ZonesSection.Zone {
            let t = Words.time(now, in: tz)
            return ZonesSection.Zone(timeZone: tz, places: [place], servers: [.init(id: place, name: place, mark: .up)], isHere: isHere,
                                     offset: tz.secondsFromGMT(for: now), hour: 12, time: t.time, period: t.period,
                                     zoneName: Words.zoneName(tz, at: now),
                                     relative: isHere ? tr("here") : Words.offset(seconds: tz.secondsFromGMT(for: now) - here.secondsFromGMT(for: now)),
                                     day: "")
        }
        var m = self
        m.sections = [
            .mac(.local(LocalSection(model: local.machine.model, readings: [.cpu, .memory, .storage, .network], snapshot: local))),
            .zones(ZonesSection(zones: [zone(here, "Seattle", isHere: true), zone(away, "Tokyo", isHere: false)], serverCount: 2,
                                unplaced: 0, isCurrent: true, now: now)),
        ]
        return m
    }
}
