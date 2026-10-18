import Foundation

/// A duration as `topo` writes one: Go's `time.Duration` text, such as
/// `5s`, `1m30s` or `1h`.
public struct Interval: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let seconds: TimeInterval

    public init(seconds: TimeInterval) { self.seconds = seconds }

    public init?(_ text: String) {
        var total = 0.0
        var number = ""
        var i = text.startIndex
        guard !text.isEmpty else { return nil }
        while i < text.endIndex {
            let c = text[i]
            if c.isNumber || c == "." {
                number.append(c)
                i = text.index(after: i)
                continue
            }
            guard let n = Double(number) else { return nil }
            number = ""
            let rest = text[i...]
            if rest.hasPrefix("ms") {
                total += n / 1000
                i = text.index(i, offsetBy: 2)
            } else {
                switch c {
                case "h": total += n * 3600
                case "m": total += n * 60
                case "s": total += n
                default: return nil
                }
                i = text.index(after: i)
            }
        }
        guard number.isEmpty, total > 0 else { return nil }
        seconds = total
    }

    /// Go's formatting, for whole seconds: `5s`, `1m30s`, `1h0m0s` reads as
    /// `1h`.
    public var description: String {
        let s = Int(seconds.rounded())
        if seconds < 1 { return "\(Int((seconds * 1000).rounded()))ms" }
        var out = ""
        if s >= 3600 { out += "\(s / 3600)h" }
        if s % 3600 >= 60 { out += "\((s % 3600) / 60)m" }
        if s % 60 > 0 || out.isEmpty { out += "\(s % 60)s" }
        return out
    }

    public static func < (a: Interval, b: Interval) -> Bool { a.seconds < b.seconds }

    /// The refresh range `topo` accepts: 1 s to 1 h.
    public var clampedToRefresh: Interval { Interval(seconds: min(3600, max(1, seconds.rounded()))) }
}
