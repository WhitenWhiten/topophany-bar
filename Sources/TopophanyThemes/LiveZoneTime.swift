import Foundation
import SwiftUI
import TopophanySections

/// A zone's time that turns each minute on the desktop, between reloads.
/// WidgetKit keeps only the system's own formats live, and those count
/// time rather than tell it, so the clock is a count up from as many hours
/// before this hour began as the clock shows, its seconds clipped away. A
/// timeline entry at each of the zone's hours sets it again
/// (`WidgetSchedule.zonesEntries`).
struct LiveZoneTime: View {
    var zone: ZonesSection.Zone
    /// The entry's time.
    var at: Date

    /// What to count from, and how the count is set.
    struct Count: Equatable {
        var from: Date
        /// Hours as "09", as the locale's clock writes them.
        var padded: Bool
        /// "0:" in the hour after midnight, where the count has no hours.
        var prefix: String
        /// As wide as the count's hours and minutes: "11:00".
        var shown: String
    }

    static func count(_ zone: ZonesSection.Zone, at date: Date, locale: Locale = L10n.locale) -> Count {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone.timeZone
        let hourStart = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        let hour = calendar.component(.hour, from: date)
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "HH:mm"
        let padded = pattern.contains("HH") || pattern.contains("hh") || pattern.contains("KK")
        // "h" runs 12, 1 … 11; "K" runs 0 … 11; "H" runs 0 … 23.
        let shown = pattern.contains("K") ? hour % 12 : pattern.contains("h") ? (hour % 12 == 0 ? 12 : hour % 12) : hour
        guard shown > 0 else {
            return Count(from: hourStart, padded: true, prefix: padded ? "00:" : "0:", shown: "00")
        }
        let digits = (padded && shown < 10 ? "0" : "") + "\(shown)"
        return Count(from: hourStart.addingTimeInterval(-Double(shown) * 3600), padded: padded, prefix: "", shown: digits + ":00")
    }

    var body: some View {
        let c = Self.count(zone, at: at)
        HStack(spacing: 0) {
            if !c.prefix.isEmpty { Text(verbatim: c.prefix) }
            Text(verbatim: c.shown).hidden()
                .overlay(alignment: .leading) {
                    Group {
                        // The stopwatch pads its hours and minutes; the timer
                        // doesn't pad its first field.
                        if c.padded || !c.prefix.isEmpty {
                            Text(.currentDate, format: .stopwatch(startingAt: c.from, showsHours: true, maxFieldCount: 3,
                                                                  maxPrecision: .seconds(1)))
                        } else {
                            Text(.currentDate, format: .timer(countingUpIn: c.from..<c.from.addingTimeInterval(2 * 86400),
                                                              showsHours: true, maxFieldCount: 3, maxPrecision: .seconds(1)))
                        }
                    }
                    .fixedSize()
                }
                .clipped()
        }
    }
}
