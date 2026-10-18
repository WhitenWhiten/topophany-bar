import Foundation

/// RFC 3339 timestamps as `topo` writes them: Go's `time.Time`, with up to
/// nine fractional digits and a `Z` or numeric offset.
public enum Timestamp {
    public static func parse(_ s: String) -> Date? {
        let b = Array(s.utf8)
        guard b.count >= 20 else { return nil }
        func num(_ i: Int, _ n: Int) -> Int? {
            guard i + n <= b.count else { return nil }
            var v = 0
            for k in i..<(i + n) {
                let c = b[k]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard let year = num(0, 4), b[4] == 45, let month = num(5, 2), b[7] == 45, let day = num(8, 2),
              b[10] == 84 || b[10] == 116, let hour = num(11, 2), b[13] == 58, let minute = num(14, 2),
              b[16] == 58, let second = num(17, 2)
        else { return nil }
        guard (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }
        var i = 19
        var fraction = 0.0
        if i < b.count, b[i] == 46 {
            i += 1
            var scale = 0.1
            let start = i
            while i < b.count, b[i] >= 48, b[i] <= 57 {
                fraction += Double(b[i] - 48) * scale
                scale /= 10
                i += 1
            }
            guard i > start else { return nil }
        }
        guard i < b.count else { return nil }
        var offset = 0
        switch b[i] {
        case 90, 122:
            guard i + 1 == b.count else { return nil }
        case 43, 45:
            guard i + 6 == b.count, let oh = num(i + 1, 2), b[i + 3] == 58, let om = num(i + 4, 2) else { return nil }
            offset = (oh * 3600 + om * 60) * (b[i] == 45 ? -1 : 1)
        default:
            return nil
        }
        // Go's zero time means "never"; treat it as absent.
        if year <= 1 { return nil }
        let days = daysFromCivil(year, month, day)
        let seconds = Double(days * 86400 + hour * 3600 + minute * 60 + second - offset) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

    public static func format(_ date: Date) -> String {
        let t = date.timeIntervalSince1970
        let whole = Int(t.rounded(.down))
        var days = whole / 86400
        var rem = whole % 86400
        if rem < 0 { rem += 86400; days -= 1 }
        let (y, m, d) = civilFromDays(days)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", y, m, d, rem / 3600, (rem / 60) % 60, rem % 60)
    }

    // Howard Hinnant's days-from-civil, proleptic Gregorian.
    private static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    private static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp + (mp < 10 ? 3 : -9)
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

extension KeyedDecodingContainer {
    /// A timestamp, or `nil` when it is absent, `null`, zero or malformed.
    func timestamp(_ key: Key) -> Date? {
        guard let s = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return Timestamp.parse(s)
    }
}
