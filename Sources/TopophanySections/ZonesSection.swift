import Foundation

/// Time zones: the servers `topo` lists, by the time zone of the place each
/// names, west to east, with This Mac's own zone among them. The times are
/// this Mac's clock; every mark is `topo`'s.
public struct ZonesSection: Sendable, Hashable {
    public struct Server: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var mark: Mark

        public init(id: String, name: String, mark: Mark) {
            self.id = id
            self.name = name
            self.mark = mark
        }
    }

    public struct Zone: Sendable, Hashable, Identifiable {
        public var timeZone: TimeZone
        /// Its places, in `topo`'s order: "Seattle", "San Jose".
        public var places: [String]
        public var servers: [Server]
        /// This Mac's zone.
        public var isHere: Bool
        /// Seconds from GMT now.
        public var offset: Int
        /// The local hour now, 0 ..< 24, minutes as its fraction.
        public var hour: Double
        /// "6:30", and "AM" or "" on a 24-hour clock.
        public var time: String
        public var period: String
        /// "PDT", "GMT+2".
        public var zoneName: String
        /// Against This Mac's zone: "here", "+3h", "−10h".
        public var relative: String
        /// "tomorrow" or "yesterday" when its date isn't This Mac's; else "".
        public var day: String

        public init(timeZone: TimeZone, places: [String], servers: [Server], isHere: Bool, offset: Int, hour: Double,
                    time: String, period: String, zoneName: String, relative: String, day: String) {
            self.timeZone = timeZone
            self.places = places
            self.servers = servers
            self.isHere = isHere
            self.offset = offset
            self.hour = hour
            self.time = time
            self.period = period
            self.zoneName = zoneName
            self.relative = relative
            self.day = day
        }

        public var id: String { timeZone.identifier }

        /// "Seattle · San Jose · Los Angeles".
        public var title: String { Words.join(places) }

        /// "6:30 AM".
        public var clock: String { period.isEmpty ? time : "\(time) \(period)" }
    }

    public var zones: [Zone]
    /// Every listed server, those without a zone included.
    public var serverCount: Int
    /// Listed servers whose place has no time zone: anycast, coordinates,
    /// or a name no zone's city matches.
    public var unplaced: Int
    /// The marks are from the last list, every one withheld.
    public var isCurrent: Bool
    public var now: Date
    /// Long past its last reload, a widget's ribbons and days are of an
    /// hour gone by: only its live clocks, offsets and places are drawn.
    public var clocksOnly = false

    public init(zones: [Zone], serverCount: Int, unplaced: Int, isCurrent: Bool, now: Date) {
        self.zones = zones
        self.serverCount = serverCount
        self.unplaced = unplaced
        self.isCurrent = isCurrent
        self.now = now
    }

    /// How light an hour of the day is drawn: 0 from 20:00 to 4:00, 1 from
    /// 8:00 to 16:00, soft between. A clock's hour, not the sun's.
    public static func daylight(_ hour: Double) -> Double {
        let raw = (1 - cos(2 * Double.pi * hour / 24)) / 2
        let t = min(1, max(0, (raw - 0.25) / 0.5))
        return t * t * (3 - 2 * t)
    }

    /// The zone's hour at `fraction` of a ribbon that runs from 12 hours
    /// before now to 12 hours after, now in the middle.
    public static func hour(_ zone: Zone, at fraction: Double) -> Double {
        let h = (zone.hour - 12 + 24 * fraction).truncatingRemainder(dividingBy: 24)
        return h < 0 ? h + 24 : h
    }

    /// Where local midnight falls on that ribbon, 0 ... 1.
    public static func midnights(_ zone: Zone) -> [Double] {
        [0.0, 1.0].map { (24 * $0 - zone.hour + 12) / 24 }.filter { $0 > 0 && $0 < 1 }
    }

    /// `count` zones, west to east, This Mac's always among them, and the
    /// ones left out: none when all of them fit.
    public func cut(keeping count: Int) -> (shown: [Zone], rest: [Zone]) {
        guard zones.count > count else { return (zones, []) }
        var keep = Set<String>()
        if let here = zones.first(where: \.isHere) { keep.insert(here.id) }
        for z in zones where keep.count < max(1, count) { keep.insert(z.id) }
        return (zones.filter { keep.contains($0.id) }, zones.filter { !keep.contains($0.id) })
    }

    /// Every server in `zones`, trouble first.
    public static func servers(_ zones: [Zone]) -> [Server] {
        Mark.troubleFirst(zones.flatMap(\.servers), by: \.mark)
    }

    /// Everything as history: the clocks stay, every mark is withheld.
    public func withheld() -> ZonesSection {
        var z = self
        z.isCurrent = false
        z.zones = zones.map { zone in
            var zone = zone
            zone.servers = zone.servers.map { .init(id: $0.id, name: $0.name, mark: .offline) }
            return zone
        }
        return z
    }
}
