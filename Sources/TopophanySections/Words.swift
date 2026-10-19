import Foundation

/// How the panel writes times, sizes and rates. Formatting only: no value
/// is rounded into a different meaning, and an unknown is never written as
/// zero.
public enum Words {
    public enum Style: Sendable { case spaced, compact }

    /// "4 s ago", "3 min ago"; compact: "4s ago", "3m ago".
    public static func ago(_ date: Date?, now: Date, style: Style = .spaced) -> String {
        guard let date else { return tr("never") }
        let s = max(0, Int(now.timeIntervalSince(date).rounded(.down)))
        switch style {
        case .spaced:
            if s < 60 { return tr("\(s) s ago") }
            if s < 3600 { return tr("\(s / 60) min ago") }
            if s < 86400 { return tr("\(s / 3600) h ago") }
            return tr("\(s / 86400) d ago")
        case .compact:
            if s < 60 { return tr("\(s)s ago") }
            if s < 3600 { return tr("\(s / 60)m ago") }
            if s < 86400 { return tr("\(s / 3600)h ago") }
            return tr("\(s / 86400)d ago")
        }
    }

    /// For VoiceOver: "4 seconds ago", in the panel's language.
    public static func agoSpoken(_ date: Date, now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L10n.localization)
        f.unitsStyle = .full
        f.dateTimeStyle = .numeric
        let d = date > now ? now : date
        return f.localizedString(for: d, relativeTo: now)
    }

    /// How long since: "4 min"; compact: "4m".
    public static func span(since date: Date, now: Date, style: Style = .spaced) -> String {
        let s = max(0, Int(now.timeIntervalSince(date).rounded(.down)))
        switch style {
        case .spaced:
            if s < 60 { return tr("\(s) s") }
            if s < 3600 { return tr("\(s / 60) min") }
            if s < 86400 { return tr("\(s / 3600) h") }
            return tr("\(s / 86400) d")
        case .compact:
            if s < 60 { return tr("\(s)s") }
            if s < 3600 { return tr("\(s / 60)m") }
            if s < 86400 { return tr("\(s / 3600)h") }
            return tr("\(s / 86400)d")
        }
    }

    /// A time of day in `zone`, its day period apart so the digits can be
    /// set large: ("6:30", "AM"), ("12:13", "中午"), or ("18:30", "") on a
    /// 24-hour clock.
    public static func time(_ date: Date, in zone: TimeZone, locale: Locale = L10n.locale) -> (time: String, period: String) {
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "HH:mm"
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = zone
        // AM and PM, or a period of the day: "中午", "凌晨".
        guard let r = pattern.range(of: "[abB]+", options: .regularExpression) else {
            f.dateFormat = pattern
            return (f.string(from: date), "")
        }
        var rest = pattern
        rest.removeSubrange(r)
        f.dateFormat = rest.trimmingCharacters(in: .whitespaces)
        let time = f.string(from: date)
        f.dateFormat = String(pattern[r])
        return (time, f.string(from: date))
    }

    /// A time and its period as the language sets them: "6:30 AM",
    /// "午後6:30", "中午12:13".
    public static func clock(_ time: String, _ period: String, locale: Locale = L10n.locale) -> String {
        guard !period.isEmpty else { return time }
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "HH:mm"
        guard let r = pattern.range(of: "[abB]+", options: .regularExpression), let h = pattern.range(of: "[hHkK]", options: .regularExpression),
              r.lowerBound < h.lowerBound else { return "\(time) \(period)" }
        return pattern[r.upperBound..<h.lowerBound].contains(" ") ? "\(period) \(time)" : period + time
    }

    /// Whether the language sets the period before the time.
    public static func periodFirst(locale: Locale = L10n.locale) -> Bool {
        clock("1", "2", locale: locale).hasPrefix("2")
    }

    /// The zone's short name at `date`: "PDT", "GMT+2".
    public static func zoneName(_ zone: TimeZone, at date: Date) -> String {
        let style: NSTimeZone.NameStyle = zone.isDaylightSavingTime(for: date) ? .shortDaylightSaving : .shortStandard
        return zone.localizedName(for: style, locale: L10n.locale) ?? zone.abbreviation(for: date) ?? zone.identifier
    }

    /// A difference between zones: "+3h", "−10h", "+5:30h".
    public static func offset(seconds: Int) -> String {
        let m = abs(seconds) / 60
        let hours = m % 60 == 0 ? "\(m / 60)" : String(format: "%d:%02d", m / 60, m % 60)
        return tr("\(seconds < 0 ? "−" : "+")\(hours)h")
    }

    /// Minutes as "1:12".
    public static func clock(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static func percent(_ v: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", v)
    }

    /// Binary sizes, as servers report them: "7.4", "16", "150".
    public static func gib(_ bytes: Int64) -> String {
        number(Double(bytes) / Double(1 << 30))
    }

    /// Decimal sizes, as macOS shows its own disks: "107.1".
    public static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1e9)
    }

    /// One decimal under 100, none from there; no trailing ".0".
    public static func number(_ v: Double) -> String {
        if v >= 100 || v.rounded() == v { return String(format: "%.0f", v.rounded()) }
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }

    /// Bytes per second: "343.9 kB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v < 1000 { return String(format: "%.0f B/s", v) }
        if v < 1e6 { return String(format: "%.1f kB/s", v / 1e3) }
        if v < 1e9 { return String(format: "%.1f MB/s", v / 1e6) }
        return String(format: "%.1f GB/s", v / 1e9)
    }

    /// Bytes per second in the menu bar's room: "344 kB/s", "1.4 MB/s".
    public static func shortRate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "kB/s", "MB/s", "GB/s"]
        var v = max(0, bytesPerSecond)
        var i = 0
        while i < units.count - 1, v >= 999.5 {
            v /= 1000
            i += 1
        }
        return (i == 0 ? String(format: "%.0f", v) : number(v)) + " " + units[i]
    }

    /// A rate without its unit when the unit is shown beside it: "343.9".
    public static func rateNumber(_ bytesPerSecond: Double) -> String {
        rate(bytesPerSecond).split(separator: " ").first.map(String.init) ?? ""
    }

    /// Joins parts with the panel's separator: "a · b".
    public static func join(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The localized name of an entry's kind, as the TUI names it.
    public static func kind(_ k: String) -> String {
        switch k {
        case "incident": tr("incident")
        case "path": tr("path")
        case "service": tr("service")
        case "node": tr("node")
        case "check": tr("check")
        case "observer": tr("observer")
        case "endpoint": tr("endpoint")
        case "link": tr("link")
        case "edge": tr("edge")
        case "platform": tr("platform")
        case "host": tr("host")
        case "vm": tr("vm")
        case "container": tr("container")
        case "router": tr("router")
        case "external": tr("external")
        case "laptop": tr("laptop")
        case "desktop": tr("desktop")
        default: k
        }
    }
}
