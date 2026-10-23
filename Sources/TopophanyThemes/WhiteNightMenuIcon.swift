import Foundation
import CoreGraphics
import TopophanySections

extension MenuBarIconAnimation {
    /// The homepage's Bayer sky, composed for a small panoramic menu bar
    /// icon `pixelHeight` pixels tall, its moon showing the status. Drawn
    /// once for each height in use, so every size keeps one dot to a pixel;
    /// Core Animation plays the cached frames without a render timer.
    public static func whiteNight(pixelHeight: Int = 48) -> MenuBarIconAnimation? {
        WhiteNightSky.kept.animation(min(96, max(12, pixelHeight)))
    }

    /// Steps from one still overlay to the next, each pixel turning over
    /// in the order the Bayer matrix dithers them: the moon changes in its
    /// own grain. The last is `to` itself.
    public static func dissolve(from: CGImage?, to: CGImage?, steps: Int = 8) -> [CGImage] {
        guard let size = (to ?? from).map({ (w: $0.width, h: $0.height) }), steps > 1,
              let old = WhiteNightSky.pixels(from, size.w, size.h), let new = WhiteNightSky.pixels(to, size.w, size.h) else {
            return to.map { [$0] } ?? []
        }
        var out: [CGImage] = []
        for k in 1..<steps {
            var mixed = old
            for y in 0..<size.h {
                for x in 0..<size.w where WhiteNightSky.bayer[(y & 7) * 8 + (x & 7)] * steps < 64 * k {
                    let o = (y * size.w + x) * 4
                    for c in 0..<4 { mixed[o + c] = new[o + c] }
                }
            }
            if let image = WhiteNightSky.image(mixed, size.w, size.h) { out.append(image) }
        }
        return out + (to.map { [$0] } ?? [])
    }
}

/// Adapted from whiten-pages/script.js: the same value noise, Bayer matrix,
/// cloud octaves, paper horizon and softly shaded disk. A closed path through
/// the noise field makes the small, slow cloud movement loop without a cut.
///
/// The disk is a moon drawn over the sky, and it says the status: full when
/// all is clear; in partial eclipse, its shadow amber, while something is
/// degraded; a blood moon, the sky beside it reddening, while something is
/// down; only its outline while what's known is incomplete, and that
/// outline in dashes while nothing current is known. Each is its own shape,
/// so without color it says the same.
enum WhiteNightSky {
    static let bayer = [
        0,32,8,40,2,34,10,42, 48,16,56,24,50,18,58,26,
        12,44,4,36,14,46,6,38, 60,28,52,20,62,30,54,22,
        3,35,11,43,1,33,9,41, 51,19,59,27,49,17,57,25,
        15,47,7,39,13,45,5,37, 63,31,55,23,61,29,53,21
    ]

    /// The frames drawn for each height in use: the last two.
    static let kept = Kept()

    final class Kept: @unchecked Sendable {
        private let lock = NSLock()
        private var animations: [(height: Int, animation: MenuBarIconAnimation)] = []

        func animation(_ height: Int) -> MenuBarIconAnimation? {
            lock.lock()
            defer { lock.unlock() }
            if let i = animations.firstIndex(where: { $0.height == height }) {
                let hit = animations.remove(at: i)
                animations.append(hit)
                return hit.animation
            }
            guard let made = WhiteNightSky.animation(height: height) else { return nil }
            animations.append((height, made))
            if animations.count > 2 { animations.removeFirst() }
            return made
        }
    }

    static func animation(height h: Int) -> MenuBarIconAnimation? {
        let count = 180
        let frames = (0..<count).compactMap { frame(phase: Double($0) / Double(count), height: h) }
        guard frames.count == count else { return nil }
        var overlays: [Mark: MenuBarIconAnimation.Overlay] = [:]
        for mark in Mark.allCases {
            guard let color = moon(mark, tinted: true, height: h), let ink = moon(mark, tinted: false, height: h) else { return nil }
            overlays[mark] = .init(color: color, ink: ink)
        }
        return MenuBarIconAnimation(id: "whiteNight", frames: frames, durations: Array(repeating: 24.0 / Double(count), count: count),
                                    overlays: overlays)
    }

    private static func fade(_ a: Double, _ b: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private static func hash(_ x: Int, _ y: Int) -> Double {
        var n = UInt32(truncatingIfNeeded: x) &* 374761393 &+ UInt32(truncatingIfNeeded: y) &* 668265263
        n = (n ^ (n >> 13)) &* 1274126177
        return Double(n ^ (n >> 16)) / 4294967296
    }

    private static func noise(_ x: Double, _ y: Double) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = fade(0, 1, x - floor(x)), fy = fade(0, 1, y - floor(y))
        let a = hash(ix, iy), b = hash(ix + 1, iy)
        let c = hash(ix, iy + 1), d = hash(ix + 1, iy + 1)
        let top = a + (b - a) * fx, bottom = c + (d - c) * fx
        return top + (bottom - top) * fy
    }

    /// Where the moon sits on a sky `h` pixels tall, 3.25 times as wide.
    struct Geometry {
        let w: Int, h: Int
        let radius: Double, cx: Double, cy: Double

        init(_ h: Int) {
            self.h = h
            w = Int((Double(h) * 3.25).rounded())
            radius = Double(h) * 0.2
            cx = Double(w) * 0.69
            cy = Double(h) * 0.38
        }

        /// How far a pixel's center lies outside the moon's rim.
        func edge(_ x: Int, _ y: Int) -> Double { hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy) - radius }

        func threshold(_ x: Int, _ y: Int) -> Double { (Double(bayer[(y & 7) * 8 + (x & 7)]) + 0.5) / 64 }

        func altitude(_ y: Int) -> Double { 1 - Double(y) / Double(h - 1) }
    }

    /// The sky alone at `phase`, `h` pixels tall; its moon is drawn over it.
    static func frame(phase: Double, height h: Int = 48) -> CGImage? {
        let g = Geometry(h), w = g.w
        let angle = phase * 2 * Double.pi
        let drift = 0.32 * sin(angle), lift = 0.16 * (cos(angle) - 1)
        // Two-point corners at full size keep the paper strip quiet against either menu bar.
        let corner = Double(h) / 12
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let altitude = g.altitude(y)
            for x in 0..<w {
                let sx = Double(x) * 44 / Double(h), sy = Double(y) * 44 / Double(h)
                let curl = noise(sx / 60 - drift * 0.4, sy / 20 + 8.1 + lift) - 0.5
                let n = 0.7 * noise(sx / 48 - drift, sy / 10 + curl + 2.4 + lift)
                    + 0.23 * noise(sx / 23 - drift * 1.4 + 31.7, sy / 5 + 13.3 + lift)
                    + 0.07 * noise(sx / 10 - drift * 1.8 + 7.2, sy / 3 + 5.8 + lift)
                let cloud = fade(0.32, 0.68, n)
                var ink = 0.56 * (0.35 + 0.65 * altitude) * (1 - cloud * 0.88)
                let edge = g.edge(x, y)
                ink *= 1 - (1 - fade(0, g.radius * 1.1, edge)) * (0.14 + sin(angle) * 0.012)
                ink *= fade(0.04, 0.62, altitude)
                // At menu bar scale a bright cloud can swallow the moon. Keep
                // a little printed sky around it so its circular silhouette reads.
                ink = max(ink, 0.26 * (1 - fade(0, g.radius * 0.9, edge)) * fade(0.04, 0.62, altitude))
                let value: UInt8 = ink > g.threshold(x, y) ? 26 : 255
                let offset = (y * w + x) * 4
                let cx = max(corner - (Double(x) + 0.5), Double(x) + 0.5 - (Double(w) - corner), 0)
                let cy = max(corner - (Double(y) + 0.5), Double(y) + 0.5 - (Double(h) - corner), 0)
                let alpha = min(1, max(0, corner + 0.5 - hypot(cx, cy)))
                for c in 0..<3 { pixels[offset + c] = UInt8(Double(value) * alpha) }
                pixels[offset + 3] = UInt8(255 * alpha)
            }
        }
        return image(pixels, w, h)
    }

    typealias RGB = (r: UInt8, g: UInt8, b: UInt8)
    static let ink: RGB = (26, 26, 26)
    static let paper: RGB = (255, 255, 255)
    /// Warning and down, deep enough to hold their color in a dither on
    /// paper.
    static let amber: RGB = (0xEA, 0x84, 0x00)
    static let blood: RGB = (0xD2, 0x26, 0x1E)

    /// The moon for `mark`, drawn still over every frame of a sky `h`
    /// pixels tall: opaque within its rim, clear elsewhere. `tinted` draws
    /// an alert in its color; otherwise in ink, as the same shape.
    static func moon(_ mark: Mark, tinted: Bool, height h: Int = 48) -> CGImage? {
        let g = Geometry(h), w = g.w, r = g.radius
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        func put(_ x: Int, _ y: Int, _ c: RGB) {
            let o = (y * w + x) * 4
            pixels[o] = c.r; pixels[o + 1] = c.g; pixels[o + 2] = c.b; pixels[o + 3] = 255
        }
        let top = max(0, Int(g.cy - 2 * r)), bottom = min(h - 1, Int(g.cy + 2 * r) + 1)
        let left = max(0, Int(g.cx - 2 * r)), right = min(w - 1, Int(g.cx + 2 * r) + 1)
        for y in top...bottom {
            for x in left...right {
                let dx = Double(x) + 0.5 - g.cx, dy = Double(y) + 0.5 - g.cy
                let edge = g.edge(x, y), t = g.threshold(x, y)
                let nx = dx / r, ny = dy / r
                let nz = sqrt(max(0, 1 - nx * nx - ny * ny))
                // Lit from the upper left, as the homepage's disk.
                let light = max(0, -0.4 * nx - 0.5 * ny + 0.768 * nz)
                let lit = 0.24 * pow(1 - light, 3)
                switch mark {
                case .up:
                    if edge < 0 { put(x, y, lit > t ? ink : paper) }
                case .degraded:
                    // The earth's shadow, a larger disk, covers its lower
                    // right; a rim keeps the lit side's round edge against
                    // a bright cloud.
                    if edge < 0 {
                        let umbra = 1 - fade(-0.8, 0.8, hypot(dx - r * 1.1, dy - r * 0.6) - r * 1.35)
                        let v = lit + (0.78 + 0.18 * (1 - light) - lit) * umbra
                        let tone = tinted ? amber : ink
                        put(x, y, edge > -1 && umbra < 0.5 ? tone : v <= t ? paper : umbra > 0.5 ? tone : ink)
                    }
                case .down:
                    if edge < 0 {
                        // Totality: in shadow throughout, brightest at the
                        // limb nearest the light.
                        let v = 0.62 + 0.32 * (1 - light) - 0.12 * pow(hypot(nx, ny), 6)
                        put(x, y, v > t ? (tinted ? blood : ink) : paper)
                    } else if tinted, edge < r * 0.9 {
                        // The printed sky beside it reddens: these dots are
                        // the sky's own, at its least.
                        let glow = 0.26 * (1 - fade(0, r * 0.9, edge)) * fade(0.04, 0.62, g.altitude(y))
                        if glow > t { put(x, y, blood) }
                    }
                case .unknown:
                    if abs(edge) < 0.7 { put(x, y, ink) }
                case .offline:
                    if abs(edge) < 0.7 {
                        let turn = (atan2(dy, dx) / (2 * .pi) * 8 + 8).truncatingRemainder(dividingBy: 1)
                        if turn < 0.55 { put(x, y, ink) }
                    }
                }
            }
        }
        return image(pixels, w, h)
    }

    static func image(_ pixels: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// An image's premultiplied pixels at `w` by `h`, top row first; clear
    /// for none.
    static func pixels(_ image: CGImage?, _ w: Int, _ h: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let image else { return pixels }
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? pixels : nil
    }
}
