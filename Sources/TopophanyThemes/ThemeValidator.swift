import Foundation

/// Checks a theme (DESIGN.md §8). It is refused, with the reason, unless:
/// - text on ink is at least 4.5:1;
/// - every pair of status colors differs by ΔE ≥ 15 (OKLab × 100);
/// - every required slot is present.
///
/// Status pairs closer than ΔE 8 under simulated color-blindness are
/// reported as advisories, not refused: no green, orange and red palette,
/// the system's and the TUI's included, keeps that margin, and every
/// status already has its own shape.
public enum ThemeValidator {
    public struct Problem: Error, Sendable, Hashable, CustomStringConvertible {
        public var description: String
        /// An advisory is reported and doesn't refuse the theme.
        public var isAdvisory = false
    }

    /// The problems that refuse a theme.
    public static func refusals(_ theme: Theme) -> [Problem] {
        validate(theme).filter { !$0.isAdvisory }
    }

    public static let minimumContrast = 4.5
    public static let minimumDelta = 15.0
    public static let minimumDeltaColorBlind = 8.0

    /// The cards renderer's status colors where a theme leaves them to the
    /// system, by appearance.
    public static let systemStatus: [Theme.Appearance: [String: RGBA]] = [
        .dark: ["up": RGBA(css: "#30D158")!, "warning": RGBA(css: "#FF9F0A")!, "down": RGBA(css: "#FF453A")!,
                "unknown": RGBA(css: "#98989F")!],
        .light: ["up": RGBA(css: "#28CD41")!, "warning": RGBA(css: "#FF9500")!, "down": RGBA(css: "#FF3B30")!,
                 "unknown": RGBA(css: "#8E8E93")!],
    ]

    public static func validate(_ theme: Theme) -> [Problem] {
        var problems: [Problem] = []
        guard theme.schema == 1 else { return [Problem(description: "schema \(theme.schema) isn't 1")] }
        let required = theme.renderer == .cells ? TokenSlots.cells : []
        for slot in required where theme.tokens[slot] == nil {
            problems.append(Problem(description: "missing token \(slot)"))
        }
        for (slot, value) in theme.tokens where RGBA(css: value) == nil && value != "system" {
            problems.append(Problem(description: "token \(slot) isn't a color: \(value)"))
        }
        if !problems.isEmpty { return problems }

        if theme.renderer == .cells, let text = theme.color("text"), let ink = theme.color("ink") {
            let ratio = contrast(text.over(ink), ink)
            if ratio < minimumContrast {
                problems.append(Problem(description: String(format: "text on ink is %.2f:1, under 4.5:1", ratio)))
            }
        }
        let appearances: [Theme.Appearance] = theme.appearance == .system ? [.dark, .light] : [theme.appearance]
        for ap in appearances {
            var status: [(String, RGBA)] = []
            for slot in TokenSlots.status {
                guard let c = theme.color(slot) ?? systemStatus[ap]?[slot] else { continue }
                status.append((slot, c))
            }
            for i in 0..<status.count {
                for j in (i + 1)..<status.count {
                    let (a, ca) = status[i]
                    let (b, cb) = status[j]
                    let d = deltaE(ca, cb)
                    if d < minimumDelta {
                        problems.append(Problem(description: String(format: "%@ and %@ differ by ΔE %.1f, under 15", a, b, d)))
                    }
                    for (name, sim) in ColorBlindness.all {
                        let ds = deltaE(sim(ca), sim(cb))
                        if ds < minimumDeltaColorBlind {
                            problems.append(Problem(description: String(format: "%@ and %@ differ by ΔE %.1f under %@, under 8",
                                                                        a, b, ds, name), isAdvisory: true))
                        }
                    }
                }
            }
        }
        return problems
    }

    // MARK: color math

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func gamma(_ c: Double) -> Double {
        let v = max(0, min(1, c))
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// WCAG relative luminance.
    static func luminance(_ c: RGBA) -> Double {
        0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    public static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// OKLab, from sRGB.
    static func oklab(_ c: RGBA) -> (Double, Double, Double) {
        let r = linear(c.r), g = linear(c.g), b = linear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// ΔE in OKLab, scaled by 100.
    public static func deltaE(_ a: RGBA, _ b: RGBA) -> Double {
        let x = oklab(a), y = oklab(b)
        return 100 * sqrt(pow(x.0 - y.0, 2) + pow(x.1 - y.1, 2) + pow(x.2 - y.2, 2))
    }
}

/// Simulated color vision deficiencies (Machado, Oliveira and Fernandes,
/// 2009, severity 1), applied in linear sRGB.
public enum ColorBlindness {
    static let protanopia = [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998]
    static let deuteranopia = [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881]
    static let tritanopia = [1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900]

    static func apply(_ m: [Double], _ c: RGBA) -> RGBA {
        let r = ThemeValidator.linear(c.r), g = ThemeValidator.linear(c.g), b = ThemeValidator.linear(c.b)
        return RGBA(ThemeValidator.gamma(m[0] * r + m[1] * g + m[2] * b),
                    ThemeValidator.gamma(m[3] * r + m[4] * g + m[5] * b),
                    ThemeValidator.gamma(m[6] * r + m[7] * g + m[8] * b), c.a)
    }

    public static let all: [(String, @Sendable (RGBA) -> RGBA)] = [
        ("protanopia", { apply(protanopia, $0) }),
        ("deuteranopia", { apply(deuteranopia, $0) }),
        ("tritanopia", { apply(tritanopia, $0) }),
    ]
}
