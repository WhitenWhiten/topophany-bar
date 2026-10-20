// Renders the disk image's window, packaging/dmg/background.png and @2x.
//
// The icon's world laid flat, as topo's geo map draws it: the land as a
// matrix of dots on the TUI's ink, the Pacific between the app and
// Applications, and the icon's arc of light from Shanghai, under the app,
// to Los Angeles, under Applications, saying where to drag. One line says
// what the app is.
//
// Finder draws names black in Light and white in Dark, whatever lies under
// them. Where they fall, the ink deepens to black, which hides the one and
// carries the other.
//
// The land is design/assets/land.bin: Natural Earth 1:110m land (public
// domain) in 0.5° cells, row 0 at 90°N, column 0 at 180°W, as topo draws it.
//
//     swift scripts/make-dmg-background.swift
//
// packaging/dmg/settings.py places the icons on this layout; change both
// together. dmgbuild joins the two PNGs into one HiDPI TIFF.

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
let landBits = [UInt8](try Data(contentsOf: root.appendingPathComponent("design/assets/land.bin")))
let out = root.appendingPathComponent("packaging/dmg")
precondition(landBits.count == 720 * 360 / 8, "land.bin should be 720 × 360 bits")

// MARK: the layout, in points (settings.py has the same numbers)

// The window shows 540 × 300 at most. The picture runs on below it, so a
// path bar or status bar only crops it; Finder paints white past a picture.
let width = 540.0, height = 340.0
let app = (x: 150.0, y: 144.0), applications = (x: 390.0, y: 144.0)
// Finder centers a 13-point name 84 points below its icon.
let names = app.y + 84

typealias RGB = (r: Double, g: Double, b: Double)
func hex(_ v: UInt32) -> RGB { (Double(v >> 16 & 255) / 255, Double(v >> 8 & 255) / 255, Double(v & 255) / 255) }
// The TUI's palette, and the icon's.
let inkTop = hex(0x121D26), inkDeep = hex(0x000000), accent = hex(0x5EEAD4), glow = hex(0xF0FDFA)
let landDay = hex(0xB4F5E8), landDusk = hex(0x2F9389), landDark = hex(0x1A4448)
let city = hex(0xFCD34D), ember = hex(0xF59E0B), muted = hex(0x6F7F8D)

func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, v)) }
func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = clamp((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t) }
func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    let t = clamp(t); return (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
}

// MARK: the map

// Shanghai lies under the app and Los Angeles under Applications.
let shanghai = (lat: 31.2, lon: 121.5), losAngeles = (lat: 34.05, lon: -118.25)
let scale = (applications.x - app.x) / (losAngeles.lon + 360 - shanghai.lon)   // points per degree
let midLat = (shanghai.lat + losAngeles.lat) / 2
func onMap(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
    var east = lon - shanghai.lon
    if east < -app.x / scale { east += 360 }
    return (app.x + east * scale, app.y - (lat - midLat) * scale)
}

func isLand(_ lat: Double, _ lon: Double) -> Bool {
    var l = (lon + 180).truncatingRemainder(dividingBy: 360)
    if l < 0 { l += 360 }
    let i = min(359, max(0, Int((90 - lat) * 2))) * 720 + min(719, Int(l * 2))
    return landBits[i >> 3] & (0x80 >> UInt8(i & 7)) != 0
}
// The land's dots sit every 2°; a cell is land when enough of it is.
let step = 2.0
func landShare(_ lat: Double, _ lon: Double) -> Double {
    var hits = 0
    for v in 0..<4 { for u in 0..<4 where isLand(lat - step / 2 + (Double(v) + 0.5) * step / 4, lon - step / 2 + (Double(u) + 0.5) * step / 4) { hits += 1 } }
    return Double(hits) / 16
}

// The arc bows north from Shanghai toward Los Angeles, as a great circle
// does on a flat map. It rises from behind the app's icon and lands on the
// folder.
let start = (x: app.x + 30, y: app.y - 20), end = (x: applications.x - 52, y: applications.y - 44)
let control = (x: (start.x + end.x) / 2, y: 32.0)
func arc(_ u: Double) -> (x: Double, y: Double) {
    let m = 1 - u
    return (m * m * start.x + 2 * m * u * control.x + u * u * end.x, m * m * start.y + 2 * m * u * control.y + u * u * end.y)
}
func arcSlope(_ u: Double) -> (x: Double, y: Double) {
    (2 * (1 - u) * (control.x - start.x) + 2 * u * (end.x - control.x), 2 * (1 - u) * (control.y - start.y) + 2 * u * (end.y - control.y))
}
// Thin where it sets out, as on the icon.
func arcWidth(_ u: Double) -> Double { 3.6 * (0.3 + 0.7 * pow(u, 0.8)) }
let arcPoints = (0...200).map { arc(Double($0) / 200) }
func distanceToArc(_ x: Double, _ y: Double) -> Double {
    arcPoints.map { ($0.x - x) * ($0.x - x) + ($0.y - y) * ($0.y - y) }.min()!.squareRoot()
}

// MARK: drawing

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ c: RGB, _ alpha: Double = 1) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }
func canvas(_ s: Double) -> CGContext {
    let c = CGContext(data: nil, width: Int(width * s), height: Int(height * s), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: height * s)
    c.scaleBy(x: s, y: -s)  // points, y down
    c.interpolationQuality = .high
    return c
}
func disc(_ c: CGContext, _ p: (x: Double, y: Double), _ r: Double, _ fill: CGColor) {
    c.setFillColor(fill)
    c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}
func place(_ c: CGContext, _ image: CGImage) {
    c.saveGState()
    c.translateBy(x: 0, y: height)
    c.scaleBy(x: 1, y: -1)
    c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    c.restoreGState()
}
let blurContext = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])
func blurred(_ image: CGImage, _ sigma: Double) -> CGImage {
    let input = CIImage(cgImage: image)
    let soft = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
    return blurContext.createCGImage(soft, from: input.extent, format: .RGBA8, colorSpace: sRGB)!
}

func render(_ s: Double) -> CGImage {
    let c = canvas(s)

    // The icon's ink, deepening smoothly to black under the names.
    let stops = (0...16).map { Double($0) / 16 }
    let ground = CGGradient(colorsSpace: sRGB, colors: stops.map { color(mix(inkTop, inkDeep, pow($0, 1.6))) } as CFArray,
                            locations: stops.map { CGFloat($0) })!
    c.drawLinearGradient(ground, start: .zero, end: CGPoint(x: 0, y: names - 12), options: [.drawsAfterEndLocation])

    // The land, in a band about the arc: clear of the words above and of
    // the names below. Dots grow and brighten toward the arc.
    for lat in stride(from: 90 - step / 2, to: -90, by: -step) {
        for lon in stride(from: -180 + step / 2, to: 180, by: step) {
            let p = onMap(lat, lon)
            guard p.x > -4, p.x < width + 4, p.y > 40, p.y < names - 16, landShare(lat, lon) >= 0.375 else { continue }
            let presence = smoothstep(52, 96, p.y) * (1 - smoothstep(app.y + 24, names - 18, p.y))
            guard presence > 0.02 else { continue }
            let near = exp(-distanceToArc(p.x, p.y) / 110)
            let tone = 0.25 + 0.75 * near
            let fill = tone > 0.4 ? mix(landDusk, landDay, (tone - 0.4) / 0.6 * 0.7) : mix(landDark, landDusk, tone / 0.4)
            disc(c, p, step * scale * (0.16 + 0.06 * near), color(fill, presence * (0.42 + 0.38 * near)))
        }
    }

    // The arc: a soft bloom, then its core, brightening toward Applications.
    func ribbon(_ w: (Double) -> Double) -> CGPath {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for k in 0...200 {
            let u = Double(k) / 200, p = arc(u), d = arcSlope(u)
            let l = (d.x * d.x + d.y * d.y).squareRoot(), h = w(u) / 2
            left.append(CGPoint(x: p.x - d.y / l * h, y: p.y + d.x / l * h))
            right.append(CGPoint(x: p.x + d.y / l * h, y: p.y - d.x / l * h))
        }
        let path = CGMutablePath()
        path.addLines(between: left + right.reversed())
        path.closeSubpath()
        for u in [0.0, 1] {
            let p = arc(u), h = w(u)
            path.addEllipse(in: CGRect(x: p.x - h / 2, y: p.y - h / 2, width: h, height: h))
        }
        return path
    }
    func fillAlong(_ c: CGContext, _ path: CGPath, _ from: CGColor, _ to: CGColor) {
        c.saveGState()
        c.addPath(path)
        c.clip()
        let g = CGGradient(colorsSpace: sRGB, colors: [from, to] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: start.x, y: start.y), end: CGPoint(x: end.x, y: end.y), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }
    let bloom = canvas(s)
    fillAlong(bloom, ribbon { arcWidth($0) * 3 }, color(accent, 0.2), color(accent, 0.9))
    place(c, blurred(bloom.makeImage()!, 6 * s))
    let core = mix(glow, accent, 0.12)
    fillAlong(c, ribbon(arcWidth), color(mix(accent, core, 0.45), 0.8), color(core))
    // The place it brings to light.
    let halo = canvas(s)
    disc(halo, end, 11, color(mix(city, ember, 0.3), 0.85))
    place(c, blurred(halo.makeImage()!, 5 * s))
    disc(c, end, 3.6, color(city))
    disc(c, end, 2, color(mix(city, glow, 0.8)))

    // One line.
    let base = CTFontCreateUIFontForLanguage(.system, 10, nil)!
    let font = CTFontCreateCopyWithAttributes(base, 10, nil, CTFontDescriptorCreateWithAttributes(
        [kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23] as CFDictionary] as CFDictionary))
    let tracking = 2.0
    let words = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "LIGHTWEIGHT NETWORK TOPOLOGY MONITOR" as CFString, [
        kCTFontAttributeName: font, kCTForegroundColorAttributeName: color(muted), kCTKernAttributeName: tracking,
    ] as CFDictionary)!)
    c.saveGState()
    c.translateBy(x: (width - CTLineGetTypographicBounds(words, nil, nil, nil) + tracking) / 2, y: 36)
    c.scaleBy(x: 1, y: -1)
    c.textPosition = .zero
    CTLineDraw(words, c)
    c.restoreGState()
    return c.makeImage()!
}

func write(_ image: CGImage, _ name: String) throws {
    let url = out.appendingPathComponent(name) as CFURL
    guard let d = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: name])
    }
    // 72 and 144 dpi, so each reads as the same size in points.
    let dpi = 72.0 * Double(image.width) / width
    CGImageDestinationAddImage(d, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(d) else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: name]) }
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try write(render(1), "background.png")
try write(render(2), "background@2x.png")
print(out.path)
