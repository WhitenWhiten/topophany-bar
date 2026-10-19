// Renders the layers of the app icon, Apps/topophany-bar/AppIcon.icon.
//
// The icon is Topophany's mark drawn at icon size: a dot-matrix Earth seen
// from 20°N 140°E and lit from the upper left, with an arc of light from
// Shanghai to Honolulu, the place it brings to light across the Pacific. The
// land is a halftone of the light on it. Three layers, each 1024 px for the
// 1024 pt canvas:
//
//   space.png  stars, and light scattered off the lit limb
//   globe.png  sea and ground, the atmosphere, and the land's dots
//   route.png  the arc, Shanghai's light and Honolulu's glow
//
// icon.json beside them stacks the layers on the ink and keeps the system's
// glass off them, so the icon stays matte in every appearance.
//
// The land is design/assets/land.bin: Natural Earth 1:110m land (public
// domain) in 0.5° cells, row 0 at 90°N, column 0 at 180°W, as topo draws it.
//
//     swift scripts/make-icon.swift
//
// To see an appearance as the system draws it, use the ictool inside Icon
// Composer (Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables):
//
//     ictool Apps/topophany-bar/AppIcon.icon --export-image --output-file icon.png \
//       --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
//
// Renditions are Default, Dark, TintedLight, TintedDark, ClearLight and ClearDark.

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
let landBits = [UInt8](try Data(contentsOf: root.appendingPathComponent("design/assets/land.bin")))
let out = root.appendingPathComponent("Apps/topophany-bar/AppIcon.icon/Assets")
precondition(landBits.count == 720 * 360 / 8, "land.bin should be 720 × 360 bits")

// MARK: the design

let size = 1024
let side = Double(size)
let radius = 368.0, centre = (x: 512.0, y: 520.0)
let facing = (lat: 20.0, lon: 140.0)        // what the globe faces
let pitch = 10.0                            // between the land's dots
let from = (lat: 31.2, lon: 121.5)          // Shanghai
let to = (lat: 21.3, lon: -157.9)           // Honolulu
let bow = 0.36                              // how far the arc bows, of its chord
let beam = 18.0                             // the arc's width where it arrives

typealias RGB = (r: Double, g: Double, b: Double)
func hex(_ v: UInt32) -> RGB { (Double(v >> 16 & 255) / 255, Double(v >> 8 & 255) / 255, Double(v & 255) / 255) }
// The TUI's palette, and the globe's from the site.
let ink = hex(0x0A1016), accent = hex(0x5EEAD4), accent2 = hex(0x7DD3FC), glow = hex(0xF0FDFA)
let landDay = hex(0xB4F5E8), landDusk = hex(0x2F9389), landDark = hex(0x1A4448)
let seaNight = hex(0x0E1D29), seaDay = hex(0x22628A), seaGlint = hex(0x4C93B8)
let groundDark = hex(0x0E2321), groundDay = hex(0x3F9682)
let city = hex(0xFCD34D), ember = hex(0xF59E0B)

// MARK: geometry

struct Vec { var x, y, z: Double }
func normalized(_ v: Vec) -> Vec { let l = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot(); return Vec(x: v.x / l, y: v.y / l, z: v.z / l) }
func dot(_ a: Vec, _ b: Vec) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, v)) }
func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = clamp((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t) }
func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    let t = clamp(t); return (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
}
func plus(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (min(1, a.r + b.r * t), min(1, a.g + b.g * t), min(1, a.b + b.b * t)) }

// The light comes from the left, above, and toward us, as on the mark.
let light = normalized(Vec(x: -0.55, y: 0.6, z: 0.58))
let halfway = normalized(Vec(x: light.x, y: light.y, z: light.z + 1))
let lat0 = facing.lat * .pi / 180, lon0 = facing.lon * .pi / 180

func isLand(_ lat: Double, _ lon: Double) -> Bool {
    var l = (lon + 180).truncatingRemainder(dividingBy: 360)
    if l < 0 { l += 360 }
    let i = min(359, max(0, Int((90 - lat) * 2))) * 720 + min(719, Int(l * 2))
    return landBits[i >> 3] & (0x80 >> UInt8(i & 7)) != 0
}
// A point on the visible disc (x right, y up, z toward us) to latitude and longitude.
func geographic(_ v: Vec) -> (lat: Double, lon: Double) {
    let lat = asin(clamp(v.z * sin(lat0) + v.y * cos(lat0), -1, 1))
    let lon = lon0 + atan2(v.x, v.z * cos(lat0) - v.y * sin(lat0))
    return (lat * 180 / .pi, lon * 180 / .pi)
}
func onScreen(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
    let la = lat * .pi / 180, lo = lon * .pi / 180
    let x = cos(la) * sin(lo - lon0)
    let y = cos(lat0) * sin(la) - sin(lat0) * cos(la) * cos(lo - lon0)
    return (centre.x + x * radius, centre.y - y * radius)
}
// The sphere under a point of the canvas; points off the disc take its edge.
func surface(_ x: Double, _ y: Double) -> Vec {
    var dx = (x - centre.x) / radius, dy = (centre.y - y) / radius
    let r = (dx * dx + dy * dy).squareRoot()
    if r > 0.999 { dx *= 0.999 / r; dy *= 0.999 / r }
    return Vec(x: dx, y: dy, z: max(0, 1 - dx * dx - dy * dy).squareRoot())
}
// How much light falls on a point: a little at night, so the globe keeps its
// shape, up to 1 facing the sun. And how sunward a point lies around the limb.
func daylight(_ v: Vec) -> Double {
    let nl = dot(v, light)
    return (0.14 + 0.86 * smoothstep(-0.15, 0.35, nl) * (0.45 + 0.55 * max(0, nl))) * pow(v.z, 0.3)
}
func sunward(_ x: Double, _ y: Double) -> Double {
    let dx = x - centre.x, dy = y - centre.y, r = (dx * dx + dy * dy).squareRoot()
    return r > 0 ? max(0, (dx * light.x - dy * light.y) / r) : 0
}

let shanghai = onScreen(from.lat, from.lon), honolulu = onScreen(to.lat, to.lon)
// Honolulu lies at dusk; its glow warms the sea around it.
func warmth(_ x: Double, _ y: Double) -> Double {
    let d = ((x - honolulu.x) * (x - honolulu.x) + (y - honolulu.y) * (y - honolulu.y)).squareRoot() / 150
    return exp(-2.5 * d * d)
}

// The arc bows up from the chord between the two places, as on the mark.
let chord = ((honolulu.x - shanghai.x) * (honolulu.x - shanghai.x) + (honolulu.y - shanghai.y) * (honolulu.y - shanghai.y)).squareRoot()
let control: (x: Double, y: Double) = {
    var nx = (honolulu.y - shanghai.y) / chord, ny = (shanghai.x - honolulu.x) / chord
    if ny > 0 { nx = -nx; ny = -ny }
    return ((shanghai.x + honolulu.x) / 2 + nx * chord * bow, (shanghai.y + honolulu.y) / 2 + ny * chord * bow)
}()
func arc(_ u: Double) -> (x: Double, y: Double) {
    let m = 1 - u
    return (m * m * shanghai.x + 2 * m * u * control.x + u * u * honolulu.x,
            m * m * shanghai.y + 2 * m * u * control.y + u * u * honolulu.y)
}
func arcSlope(_ u: Double) -> (x: Double, y: Double) {
    (2 * (1 - u) * (control.x - shanghai.x) + 2 * u * (honolulu.x - control.x),
     2 * (1 - u) * (control.y - shanghai.y) + 2 * u * (honolulu.y - control.y))
}
// The arc thins toward Shanghai, so it reads as light setting out.
func arcWidth(_ u: Double) -> Double { beam * (0.3 + 0.7 * pow(u, 0.8)) }
let arcPoints = (0...400).map { arc(Double($0) / 400) }
func nearestOnArc(_ x: Double, _ y: Double) -> (distance: Double, u: Double) {
    var best = Double.infinity, at = 0
    for (k, p) in arcPoints.enumerated() {
        let d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
        if d < best { best = d; at = k }
    }
    return (best.squareRoot(), Double(at) / 400)
}

// MARK: drawing

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func canvas() -> CGContext {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: side)
    c.scaleBy(x: 1, y: -1)  // y down, as in the mark
    c.interpolationQuality = .high
    return c
}
func color(_ c: RGB, _ alpha: Double = 1) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }
func disc(_ c: CGContext, _ p: (x: Double, y: Double), _ r: Double, _ fill: CGColor) {
    c.setFillColor(fill)
    c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}
func place(_ c: CGContext, _ image: CGImage) {
    c.saveGState()
    c.translateBy(x: 0, y: side)
    c.scaleBy(x: 1, y: -1)
    c.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    c.restoreGState()
}
let blurContext = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])
func blurred(_ image: CGImage, _ sigma: Double) -> CGImage {
    let input = CIImage(cgImage: image)
    let soft = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
    return blurContext.createCGImage(soft, from: input.extent, format: .RGBA8, colorSpace: sRGB)!
}
func write(_ image: CGImage, _ name: String) throws {
    let url = out.appendingPathComponent(name) as CFURL
    guard let d = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: name])
    }
    CGImageDestinationAddImage(d, image, nil)
    guard CGImageDestinationFinalize(d) else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: name]) }
}

// Smooth parts are painted a pixel at a time, with straight alpha.
struct Pixels {
    var px = [Double](repeating: 0, count: size * size * 4)
    mutating func over(_ x: Int, _ y: Int, _ c: RGB, _ a: Double) {
        guard a > 0 else { return }
        let o = (y * size + x) * 4, below = px[o + 3], a2 = a + below * (1 - a)
        px[o] = (c.r * a + px[o] * below * (1 - a)) / a2
        px[o + 1] = (c.g * a + px[o + 1] * below * (1 - a)) / a2
        px[o + 2] = (c.b * a + px[o + 2] * below * (1 - a)) / a2
        px[o + 3] = a2
    }
    var image: CGImage {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            let a = clamp(px[i * 4 + 3])
            for k in 0..<3 { bytes[i * 4 + k] = UInt8(clamp(px[i * 4 + k]) * a * 255 + 0.5) }
            bytes[i * 4 + 3] = UInt8(a * 255 + 0.5)
        }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)!
    }
}

// MARK: the land, cell by cell

// The land's dots sit on a square grid, as cells do in a terminal. Each cell
// is land when most of it is.
let cells = Int((radius / pitch).rounded(.up)) + 2, grid = 2 * cells
func cellCentre(_ i: Int, _ j: Int) -> (x: Double, y: Double) {
    (centre.x + (Double(i - cells) + 0.5) * pitch, centre.y + (Double(j - cells) + 0.5) * pitch)
}
var landShare = [Double](repeating: 0, count: grid * grid)
for j in 0..<grid {
    for i in 0..<grid {
        let c = cellCentre(i, j)
        var hits = 0
        for v in -1...1 {
            for u in -1...1 {
                let x = c.x + Double(u) * pitch / 3, y = c.y + Double(v) * pitch / 3
                let dx = x - centre.x, dy = y - centre.y
                guard dx * dx + dy * dy < radius * radius else { continue }
                let g = geographic(surface(x, y))
                if isLand(g.lat, g.lon) { hits += 1 }
            }
        }
        landShare[j * grid + i] = Double(hits) / 9
    }
}
// The ground under the dots blends the cells, so land shows as a soft glow.
func landUnder(_ x: Double, _ y: Double) -> Double {
    let fx = (x - centre.x) / pitch + Double(cells) - 0.5, fy = (y - centre.y) / pitch + Double(cells) - 0.5
    let i = Int(fx.rounded(.down)), j = Int(fy.rounded(.down)), tx = fx - Double(i), ty = fy - Double(j)
    func at(_ a: Int, _ b: Int) -> Double { a >= 0 && b >= 0 && a < grid && b < grid ? landShare[b * grid + a] : 0 }
    return (at(i, j) * (1 - tx) + at(i + 1, j) * tx) * (1 - ty) + (at(i, j + 1) * (1 - tx) + at(i + 1, j + 1) * tx) * ty
}

// MARK: space

func space() -> CGImage {
    let c = canvas()
    // Light scattered off the lit limb into space.
    var haze = Pixels()
    for y in 0..<size {
        for x in 0..<size {
            let fx = Double(x) + 0.5, fy = Double(y) + 0.5
            let r = ((fx - centre.x) * (fx - centre.x) + (fy - centre.y) * (fy - centre.y)).squareRoot()
            guard r > radius - 2 else { continue }
            haze.over(x, y, accent2, 0.12 * exp(-(r - radius) / (0.3 * radius)) * (0.2 + 0.8 * pow(sunward(fx, fy), 1.5)))
        }
    }
    place(c, haze.image)
    // A few faint stars, the same ones every time.
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    func random() -> Double {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Double(seed % 1_000_000) / 1_000_000
    }
    for _ in 0..<28 {
        let x = random() * side, y = random() * side, m = random()
        let r = ((x - centre.x) * (x - centre.x) + (y - centre.y) * (y - centre.y)).squareRoot()
        if r < radius * 1.07 + 24 { continue }
        disc(c, (x, y), 1.5 * (1 + m), color(mix(ink, mix(accent2, glow, 0.4), 0.22 + 0.3 * m * m)))
    }
    return c.makeImage()!
}

// MARK: the globe

func globe() -> CGImage {
    let c = canvas()
    var ground = Pixels()
    let air = 0.07 * radius
    for y in 0..<size {
        for x in 0..<size {
            let fx = Double(x) + 0.5, fy = Double(y) + 0.5
            let r = ((fx - centre.x) * (fx - centre.x) + (fy - centre.y) * (fy - centre.y)).squareRoot()
            guard r < radius + air + 2 else { continue }
            let v = surface(fx, fy), level = daylight(v), sun = sunward(fx, fy)
            let inside = clamp(radius + 0.5 - r)
            // The atmosphere, brightest sunward.
            if inside < 1 {
                let f = clamp(1 - (r - radius) / air)
                ground.over(x, y, mix(accent2, glow, 0.2), pow(f, 2.4) * (0.04 + 0.6 * pow(sun, 1.6)) * (1 - inside))
            }
            guard inside > 0 else { continue }
            let land = landUnder(fx, fy)
            var p = mix(mix(seaNight, seaDay, level), mix(groundDark, groundDay, level), land)
            p = mix(p, seaGlint, pow(max(0, dot(v, halfway)), 30) * 0.45 * (1 - land))
            // The limb catches the light, and keeps a faint edge at night.
            let nl = dot(v, light)
            let limb = exp(-(radius - r) / radius / 0.016) * (0.3 + 0.85 * pow(sun, 1.3)) * (0.35 + 0.65 * smoothstep(-0.15, 0.35, nl))
            p = mix(p, mix(accent2, glow, 0.35), limb)
            p = plus(p, mix(ember, city, 0.5), warmth(fx, fy) * 0.2)
            ground.over(x, y, p, inside)
        }
    }
    place(c, ground.image)

    // The land as a halftone: each cell's dot grows with the light on it.
    for j in 0..<grid {
        for i in 0..<grid where landShare[j * grid + i] >= 0.5 {
            let p = cellCentre(i, j)
            let dx = p.x - centre.x, dy = p.y - centre.y
            guard (dx * dx + dy * dy).squareRoot() < radius - 0.6 * pitch else { continue }
            // Clear the land around Shanghai's light and under the arc.
            let fromShanghai = ((p.x - shanghai.x) * (p.x - shanghai.x) + (p.y - shanghai.y) * (p.y - shanghai.y)).squareRoot()
            guard fromShanghai > 22 else { continue }
            let near = nearestOnArc(p.x, p.y)
            guard near.distance > 8 * (0.5 + 0.5 * near.u) + beam / 2 else { continue }
            let v = surface(p.x, p.y), w = warmth(p.x, p.y)
            let tone = clamp(clamp(1.5 * max(0, dot(v, light))) + 0.6 * w)
            let lit = max(tone, 0.18)
            var fill = lit > 0.33 ? mix(landDusk, landDay, pow((lit - 0.33) / 0.67, 0.8)) : mix(landDark, landDusk, lit * 3)
            fill = mix(ink, fill, 0.5 + 0.5 * v.z.squareRoot())
            fill = mix(fill, mix(city, glow, 0.3), 0.5 * w)
            disc(c, p, pitch * (0.24 + 0.24 * pow(tone, 0.8)) * (0.75 + 0.25 * v.z.squareRoot()), color(fill))
        }
    }
    return c.makeImage()!
}

// MARK: the route

// A ribbon along the arc, as one shape, with round ends.
func ribbon(_ width: (Double) -> Double) -> CGPath {
    var left: [CGPoint] = [], right: [CGPoint] = []
    for k in 0...300 {
        let u = Double(k) / 300, p = arc(u), d = arcSlope(u)
        let l = (d.x * d.x + d.y * d.y).squareRoot(), w = width(u) / 2
        left.append(CGPoint(x: p.x - d.y / l * w, y: p.y + d.x / l * w))
        right.append(CGPoint(x: p.x + d.y / l * w, y: p.y - d.x / l * w))
    }
    let path = CGMutablePath()
    path.addLines(between: left + right.reversed())
    path.closeSubpath()
    for u in [0.0, 1] {
        let p = arc(u), w = width(u)
        path.addEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
    }
    return path
}
// Fills a shape with a gradient that runs from Shanghai to Honolulu.
func fillAlong(_ c: CGContext, _ path: CGPath, _ start: CGColor, _ end: CGColor) {
    c.saveGState()
    c.addPath(path)
    c.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: [start, end] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: shanghai.x, y: shanghai.y), end: CGPoint(x: honolulu.x, y: honolulu.y),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}

func route() -> CGImage {
    let c = canvas()
    let bloom = canvas()
    fillAlong(bloom, ribbon { arcWidth($0) * 2.8 }, color(accent, 0.25), color(accent, 1))
    place(c, blurred(bloom.makeImage()!, 16))
    let core = mix(glow, accent, 0.12)
    fillAlong(c, ribbon(arcWidth), color(mix(accent, core, 0.45), 0.85), color(core))

    disc(c, shanghai, 12, color(mix(city, glow, 0.1)))
    let halo = canvas()
    disc(halo, honolulu, 52, color(mix(city, ember, 0.3), 0.9))
    place(c, blurred(halo.makeImage()!, 22))
    disc(c, honolulu, 17, color(city))
    disc(c, honolulu, 9.35, color(mix(city, glow, 0.8)))
    return c.makeImage()!
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try write(space(), "space.png")
try write(globe(), "globe.png")
try write(route(), "route.png")
print(out.path)
