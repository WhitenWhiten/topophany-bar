import Foundation
import SwiftUI
import Testing
import TopophanySections
@testable import TopophanyThemes

/// The live clock is a count, its seconds clipped away: what shows must be
/// the time the clock would write, in every locale's way of writing it.
@Suite struct LiveZoneTimeTests {
    func zone(_ id: String, at date: Date) -> ZonesSection.Zone {
        let tz = TimeZone(identifier: id)!
        let (time, period) = Words.time(date, in: tz)
        return .init(timeZone: tz, places: ["x"], servers: [], isHere: false, offset: 0, hour: 0, time: time, period: period,
                     zoneName: "", relative: "", day: "")
    }

    /// What the widget shows: the prefix, then as much of the count as
    /// `shown` is wide.
    func shows(_ c: LiveZoneTime.Count, at date: Date) -> String {
        let count = c.padded || !c.prefix.isEmpty
            ? String(SystemFormatStyle.Stopwatch.stopwatch(startingAt: c.from, showsHours: true, maxFieldCount: 3,
                                                           maxPrecision: .seconds(1)).format(date).characters)
            : String(SystemFormatStyle.Timer.timer(countingUpIn: c.from..<c.from.addingTimeInterval(2 * 86400), showsHours: true,
                                                   maxFieldCount: 3, maxPrecision: .seconds(1)).format(date).characters)
        return c.prefix + count.prefix(c.shown.count)
    }

    @Test func readsAsTheClockWrites() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let base = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 18, minute: 26, second: 41)))
        // Every hour of a day, so midnight, noon and the hours either side.
        let times = (0..<24).map { base.addingTimeInterval(Double($0) * 3600 + 17 * 60) }
        // A 12-hour clock, two 24-hour clocks, and one padded.
        for l in ["en", "ja", "zh-Hans", "en_GB"] {
            try L10n.with(l) {
                for id in ["America/Los_Angeles", "Asia/Shanghai", "Asia/Kolkata", "Pacific/Chatham"] {
                    for t in times {
                        let z = zone(id, at: t)
                        let c = LiveZoneTime.count(z, at: t)
                        #expect(shows(c, at: t) == z.time, "\(l) \(id) \(t)")
                        // And still, a minute before the hour ends.
                        let interval = try #require({ () -> DateInterval? in
                            var cal = Calendar(identifier: .gregorian)
                            cal.timeZone = z.timeZone
                            return cal.dateInterval(of: .hour, for: t)
                        }())
                        let late = interval.end.addingTimeInterval(-30)
                        #expect(shows(c, at: late) == zone(id, at: late).time, "\(l) \(id) \(late)")
                    }
                }
            }
        }
    }

    /// On the morning the clocks go forward, the count still reads the
    /// time: it counts from the hour, not from midnight.
    @Test func throughTheChangeToSummerTime() throws {
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = la
        let t = try #require(cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 40)))
        L10n.with("en") {
            let z = zone("America/Los_Angeles", at: t)
            #expect(z.time == "3:40")
            #expect(shows(LiveZoneTime.count(z, at: t), at: t) == "3:40")
        }
    }
}
