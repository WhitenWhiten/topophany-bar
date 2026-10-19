import Foundation

/// The code that lays out every section for every surface. A theme names
/// one; the renderer owns glyph shapes, layout and what each token slot
/// means.
public enum RendererID: String, Sendable, Hashable, Codable, CaseIterable {
    case cards
    case cells
}

/// A theme is data: a renderer's name and its tokens (DESIGN.md §8). The
/// built-in themes are read through this same type, from JSON compiled in.
public struct Theme: Sendable, Hashable, Codable, Identifiable {
    public enum Appearance: String, Sendable, Hashable, Codable {
        case light, dark
        /// Follows the system (or the panel setting).
        case system
    }

    /// The type a theme is set in. `cards` draws SF Pro, SF Pro Rounded or
    /// New York, and SF Pro for any other family; `cells` always draws SF
    /// Mono, which its grid is measured in.
    public struct Font: Sendable, Hashable, Codable {
        public var family: String
        public var size: Double

        public init(family: String, size: Double) {
            self.family = family
            self.size = size
        }
    }

    public var schema: Int
    public var id: String
    public var name: String
    public var renderer: RendererID
    public var appearance: Appearance
    /// Slot name → color, such as `"ink": "#0A1016"`. A cards theme may
    /// leave slots out; they fall back to the system's.
    public var tokens: [String: String]
    /// A cards theme that follows the system may give slots per
    /// appearance: these are drawn in dark, over `tokens`.
    public var dark: [String: String]
    /// Drawn in light, over `tokens`.
    public var light: [String: String]
    public var font: Font?

    public init(schema: Int = 1, id: String, name: String, renderer: RendererID, appearance: Appearance,
                tokens: [String: String], dark: [String: String] = [:], light: [String: String] = [:], font: Font? = nil) {
        self.schema = schema
        self.id = id
        self.name = name
        self.renderer = renderer
        self.appearance = appearance
        self.tokens = tokens
        self.dark = dark
        self.light = light
        self.font = font
    }

    enum CodingKeys: String, CodingKey { case schema, id, name, renderer, appearance, tokens, dark, light, font }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        renderer = try c.decode(RendererID.self, forKey: .renderer)
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system
        tokens = try c.decodeIfPresent([String: String].self, forKey: .tokens) ?? [:]
        dark = try c.decodeIfPresent([String: String].self, forKey: .dark) ?? [:]
        light = try c.decodeIfPresent([String: String].self, forKey: .light) ?? [:]
        font = try c.decodeIfPresent(Font.self, forKey: .font)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(renderer, forKey: .renderer)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(tokens, forKey: .tokens)
        if !dark.isEmpty { try c.encode(dark, forKey: .dark) }
        if !light.isEmpty { try c.encode(light, forKey: .light) }
        try c.encodeIfPresent(font, forKey: .font)
    }

    /// A slot's color in every appearance.
    public func color(_ slot: String) -> RGBA? { tokens[slot].flatMap(RGBA.init(css:)) }

    /// A slot's color in dark or light: that appearance's own, or the
    /// theme's.
    public func color(_ slot: String, dark isDark: Bool) -> RGBA? {
        ((isDark ? dark : light)[slot] ?? tokens[slot]).flatMap(RGBA.init(css:))
    }
}

/// The slots each renderer reads.
public enum TokenSlots {
    /// `cells` requires every one.
    public static let cells = ["ink", "inkHigh", "selection", "key", "line", "track", "text", "muted", "faint",
                               "accent", "accent2", "kind", "up", "warning", "down", "unknown"]
    /// `cards` reads these; missing ones fall back to the system's.
    public static let cards = ["accent", "accent2", "card", "cardEdge", "panelMaterial", "fill", "fill2"]
    /// Status colors, optional for `cards`.
    public static let status = ["up", "warning", "down", "unknown"]
}

/// A color in sRGB, 0…1.
public struct RGBA: Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `#RGB`, `#RRGGBB`, `#RRGGBBAA` or `rgba(r, g, b, a)`.
    public init?(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
            if hex.count == 6 {
                self.init(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
            } else {
                self.init(Double((v >> 24) & 255) / 255, Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255,
                          Double(v & 255) / 255)
            }
            return
        }
        guard s.hasPrefix("rgb"), let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { return nil }
        let parts = s[s.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let n = parts.compactMap(Double.init)
        guard n.count == parts.count else { return nil }
        self.init(n[0] / 255, n[1] / 255, n[2] / 255, n.count == 4 ? n[3] : 1)
    }

    /// `t` of the way from `self` to `other`, as CSS `color-mix` in sRGB.
    public func mix(_ other: RGBA, _ t: Double) -> RGBA {
        RGBA(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }

    public func opacity(_ o: Double) -> RGBA { RGBA(r, g, b, a * o) }

    /// Composited over an opaque background.
    public func over(_ bg: RGBA) -> RGBA {
        RGBA(r * a + bg.r * (1 - a), g * a + bg.g * (1 - a), b * a + bg.b * (1 - a), 1)
    }
}
