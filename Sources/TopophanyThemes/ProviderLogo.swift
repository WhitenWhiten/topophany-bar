import SwiftUI
import TopophanySections

/// Providers' logos as outlines, so they are crisp at any size. A logo
/// only says who runs a node; it is drawn in the text's color in Native,
/// where color is kept for health, and in its brand's in Terminal, as the
/// TUI draws it.
enum ProviderLogo {
    struct Outline: @unchecked Sendable {
        /// Its longer side is 1.
        var size: CGSize
        /// How large it is drawn, its longer side against the box's: a solid
        /// or a squat logo looks larger or smaller than its extent.
        var optical: Double
        /// What is filled: a glyph's lines are made outlines here, once.
        var path: Path
    }

    static let parsed: [String: Outline] = outlines.mapValues { w, h, k, line, d in
        let path = parse(d)
        return Outline(size: CGSize(width: w, height: h), optical: k,
                       path: line > 0 ? path.strokedPath(StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)) : path)
    }

    static func outline(_ key: String) -> Outline? { parsed[key] }

    /// What stands for a node where its provider has no logo, or it names
    /// one the app doesn't know: a glyph for its kind.
    static func glyph(kind: String) -> String {
        switch kind.lowercased() {
        case "edge", "cdn": "glyph.edge"
        case "platform", "paas", "serverless": "glyph.platform"
        default: "glyph.server"
        }
    }

    /// The outline for a provider: its logo, or its node's kind's glyph;
    /// nil when it names none.
    static func key(provider: String, kind: String) -> String? {
        if let known = Provider.known(provider), known.hasLogo { return known.key }
        return provider.trimmingCharacters(in: .whitespaces).isEmpty ? nil : glyph(kind: kind)
    }

    /// The logo centered in `rect`, its longer side the shorter of `rect`'s
    /// sides at the logo's optical size.
    static func path(_ key: String, in rect: CGRect) -> Path? {
        guard let o = parsed[key] else { return nil }
        let k = min(rect.width, rect.height) * o.optical
        let w = o.size.width * k, h = o.size.height * k
        let t = CGAffineTransform(translationX: rect.midX - w / 2, y: rect.midY - h / 2).scaledBy(x: k, y: k)
        return o.path.applying(t)
    }

    /// An outline written as absolute M, L, Q, C and Z, numbers apart by
    /// spaces: what scripts/make-providers.py writes.
    static func parse(_ d: String) -> Path {
        var p = Path()
        var command: Character = "M"
        var numbers: [Double] = []
        func flush() {
            let n = numbers
            switch command {
            case "M" where n.count == 2: p.move(to: CGPoint(x: n[0], y: n[1]))
            case "L" where n.count == 2: p.addLine(to: CGPoint(x: n[0], y: n[1]))
            case "Q" where n.count == 4: p.addQuadCurve(to: CGPoint(x: n[2], y: n[3]), control: CGPoint(x: n[0], y: n[1]))
            case "C" where n.count == 6:
                p.addCurve(to: CGPoint(x: n[4], y: n[5]), control1: CGPoint(x: n[0], y: n[1]), control2: CGPoint(x: n[2], y: n[3]))
            case "Z": p.closeSubpath()
            default: assertionFailure("bad segment \(command) \(n)")
            }
            numbers.removeAll(keepingCapacity: true)
        }
        var token = ""
        func number() {
            if !token.isEmpty, let v = Double(token) { numbers.append(v) }
            token = ""
        }
        var started = false
        for c in d {
            if c.isLetter {
                number()
                if started { flush() }
                command = c
                started = true
            } else if c == " " {
                number()
            } else {
                token.append(c)
            }
        }
        number()
        if started { flush() }
        return p
    }
}

// MARK: Native

/// A provider's logo in one color, filling its frame.
struct ProviderGlyph: View {
    var key: String
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            if let p = ProviderLogo.path(key, in: CGRect(origin: .zero, size: size)) {
                ctx.fill(p, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// What stands for a node on its card: its provider's logo, its kind's
/// glyph where the app has no logo for its provider, or its kind's symbol
/// where it names no provider.
struct NodeAvatar: View {
    var provider: String
    var kind: String
    var size: Double
    var p: CardsPalette
    /// A symbol of the node's own, such as This Mac's model.
    var symbol: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 8 / 28, style: .continuous)
        shape.fill(p.fill2)
            .overlay { face }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder var face: some View {
        if let symbol {
            Image(systemName: symbol).font(.system(size: size * 13 / 28)).foregroundStyle(p.l2)
        } else if let key = ProviderLogo.key(provider: provider, kind: kind) {
            ProviderGlyph(key: key, color: p.l2).frame(width: size * 0.56, height: size * 0.56)
        } else {
            Image(systemName: Self.symbol(kind)).font(.system(size: size * 13 / 28)).foregroundStyle(p.l2)
        }
    }

    /// A symbol for what a node is, where it names no provider.
    static func symbol(_ kind: String) -> String {
        switch kind.lowercased() {
        case "laptop": "laptopcomputer"
        case "desktop", "workstation": "desktopcomputer"
        case "router", "gateway", "firewall": "wifi.router"
        case "edge": "network"
        case "platform": "square.stack.3d.up"
        case "container": "shippingbox"
        case "nas", "storage": "externaldrive.connected.to.line.below"
        case "phone": "candybarphone"
        default: "server.rack"
        }
    }
}

// MARK: Terminal

extension CellsPalette {
    /// A logo's color: its brand's, 12% toward the text as the TUI mixes it,
    /// and further while it is too dark to read on the ink. A glyph, which
    /// has no brand, is muted.
    func logo(_ provider: Provider?) -> RGBA {
        guard let c = provider?.color else { return muted }
        let brand = RGBA(Double((c >> 16) & 255) / 255, Double((c >> 8) & 255) / 255, Double(c & 255) / 255)
        var t = 0.12
        var out = brand.mix(text, t)
        while ThemeValidator.contrast(out, ink) < 3, t < 1 {
            t += 0.08
            out = brand.mix(text, min(1, t))
        }
        return out
    }
}

extension CellCanvas {
    /// A logo as a Nerd Font draws one: from the left of its cell into the
    /// space after it, about a letter and a half wide, centered on the line.
    static func drawLogo(_ ctx: inout GraphicsContext, _ key: String, x: Double, y: Double, color: RGBA, metrics m: CellMetrics) {
        let inset = max(0.5, m.cell * 0.06)
        let side = min(m.fontSize * 0.86, 2 * m.cell - 3 * inset)
        let box = CGRect(x: x + inset, y: y + (m.line - side) / 2 + 0.03 * m.fontSize, width: side, height: side)
        if let p = ProviderLogo.path(key, in: box) { ctx.fill(p, with: .color(Color(color))) }
    }
}
