import Foundation
import CoreGraphics

extension MenuBarIconAnimation {
    /// The homepage's Bayer sky, composed for a small panoramic menu bar icon.
    /// Generated once; Core Animation plays the cached frames without a render timer.
    public static let whiteNight: MenuBarIconAnimation? = {
        let count = 180
        let frames = (0..<count).compactMap { WhiteNightSky.frame(phase: Double($0) / Double(count)) }
        guard frames.count == count else { return nil }
        return MenuBarIconAnimation(id: "whiteNight", frames: frames,
                                   durations: Array(repeating: 24.0 / Double(count), count: count))
    }()
}

/// Adapted from whiten-pages/script.js: the same value noise, Bayer matrix,
/// cloud octaves, paper horizon and softly shaded disk. A closed path through
/// the noise field makes the small, slow cloud movement loop without a cut.
enum WhiteNightSky {
    static let bayer = [
        0,32,8,40,2,34,10,42, 48,16,56,24,50,18,58,26,
        12,44,4,36,14,46,6,38, 60,28,52,20,62,30,54,22,
        3,35,11,43,1,33,9,41, 51,19,59,27,49,17,57,25,
        15,47,7,39,13,45,5,37, 63,31,55,23,61,29,53,21
    ]

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

    static func frame(phase: Double) -> CGImage? {
        let w = 156, h = 48
        let angle = phase * 2 * Double.pi
        let drift = 0.32 * sin(angle), lift = 0.16 * (cos(angle) - 1)
        let radius = Double(h) * 0.2
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let altitude = 1 - Double(y) / Double(h - 1)
            for x in 0..<w {
                let sx = Double(x) * 44 / Double(h), sy = Double(y) * 44 / Double(h)
                let curl = noise(sx / 60 - drift * 0.4, sy / 20 + 8.1 + lift) - 0.5
                let n = 0.7 * noise(sx / 48 - drift, sy / 10 + curl + 2.4 + lift)
                    + 0.23 * noise(sx / 23 - drift * 1.4 + 31.7, sy / 5 + 13.3 + lift)
                    + 0.07 * noise(sx / 10 - drift * 1.8 + 7.2, sy / 3 + 5.8 + lift)
                let cloud = fade(0.32, 0.68, n)
                var ink = 0.56 * (0.35 + 0.65 * altitude) * (1 - cloud * 0.88)
                let dx = Double(x) + 0.5 - Double(w) * 0.69
                let dy = Double(y) + 0.5 - Double(h) * 0.38
                let edge = hypot(dx, dy) - radius
                ink *= 1 - (1 - fade(0, radius * 1.1, edge)) * (0.14 + sin(angle) * 0.012)
                ink *= fade(0.04, 0.62, altitude)
                // At menu bar scale a bright cloud can swallow the disk. Keep
                // a little printed sky around it so its circular silhouette reads.
                ink = max(ink, 0.26 * (1 - fade(0, radius * 0.9, edge)) * fade(0.04, 0.62, altitude))
                if edge < 0.75 {
                    let nx = dx / radius, ny = dy / radius
                    let nz = sqrt(max(0, 1 - nx * nx - ny * ny))
                    let light = max(0, -0.4 * nx - 0.5 * ny + 0.768 * nz)
                    let shade = 0.24 * pow(1 - light, 3)
                    ink += (shade - ink) * (1 - fade(-0.75, 0.75, edge))
                }
                let value: UInt8 = ink > (Double(bayer[(y & 7) * 8 + (x & 7)]) + 0.5) / 64 ? 26 : 255
                let offset = (y * w + x) * 4
                // Two-point corners keep the paper strip quiet against either menu bar.
                let cx = max(4 - (Double(x) + 0.5), Double(x) + 0.5 - Double(w - 4), 0)
                let cy = max(4 - (Double(y) + 0.5), Double(y) + 0.5 - Double(h - 4), 0)
                let alpha = min(1, max(0, 4.5 - hypot(cx, cy)))
                for c in 0..<3 { pixels[offset + c] = UInt8(Double(value) * alpha) }
                pixels[offset + 3] = UInt8(255 * alpha)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
