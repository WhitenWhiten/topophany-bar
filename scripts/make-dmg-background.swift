// Renders the disk image's window, packaging/dmg/background.png and @2x.
//
// The world laid flat in the icon's dither: the land in ink on paper, in the
// homepage's 8×8 ordered (Bayer) dither, the Pacific between the app and
// Applications, and a route in ink from Shanghai, under the app, to Los
// Angeles, under Applications, saying where to drag. One line says what the
// app is.
//
// A cell is 2 points, a degree of the map, the grain of the icon's own dither
// at the 128 points the window shows it: 2 pixels in background.png, 4 in
// @2x.
//
// Finder draws names black in Light and white in Dark, whatever lies under
// them. Under the app's name the paper is clear, so it reads in Light and
// stays out of the way in Dark; Applications has none.
//
// The land is design/assets/land.bin: Natural Earth 1:110m land (public
// domain) in 0.5° cells, row 0 at 90°N, column 0 at 180°W, as topo draws it.
//
//     swift scripts/make-dmg-background.swift
//
// packaging/dmg/settings.py places the icons on this layout; change both
// together. dmgbuild joins the two PNGs into one HiDPI TIFF.

import CoreGraphics
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
let cell = 2.0
let columns = Int(width / cell), rows = Int(height / cell)

let ink = CGColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255, alpha: 1)
let paper = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let muted = CGColor(srgbRed: 0x80 / 255, green: 0x80 / 255, blue: 0x80 / 255, alpha: 1)
let bayer = [
    0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26,
    12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
    3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
    15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21,
]
func threshold(_ i: Int, _ j: Int) -> Double { (Double(bayer[(j & 7) * 8 + (i & 7)]) + 0.5) / 64 }

func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, v)) }
func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = clamp((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t) }

// MARK: the map

// Shanghai lies under the app and Los Angeles under Applications.
let shanghai = (lat: 31.2, lon: 121.5), losAngeles = (lat: 34.05, lon: -118.25)
let scale = (applications.x - app.x) / (losAngeles.lon + 360 - shanghai.lon)   // points per degree
let midLat = (shanghai.lat + losAngeles.lat) / 2
// The point's place on the globe.
func geographic(_ x: Double, _ y: Double) -> (lat: Double, lon: Double) {
    (midLat - (y - app.y) / scale, shanghai.lon + (x - app.x) / scale)
}

func isLand(_ lat: Double, _ lon: Double) -> Bool {
    guard lat > -90, lat < 90 else { return false }
    var l = (lon + 180).truncatingRemainder(dividingBy: 360)
    if l < 0 { l += 360 }
    let i = min(359, max(0, Int((90 - lat) * 2))) * 720 + min(719, Int(l * 2))
    return landBits[i >> 3] & (0x80 >> UInt8(i & 7)) != 0
}
// A cell is land when most of it is.
func isLandCell(_ x: Double, _ y: Double) -> Bool {
    var hits = 0
    for v in 0..<4 {
        for u in 0..<4 {
            let g = geographic(x + (Double(u) + 0.5) * cell / 4, y + (Double(v) + 0.5) * cell / 4)
            if isLand(g.lat, g.lon) { hits += 1 }
        }
    }
    return hits >= 8
}

// The route bows north from Shanghai toward Los Angeles, as a great circle
// does on a flat map. It rises from behind the app's icon and lands on the
// folder.
let start = (x: app.x + 30, y: app.y - 20), end = (x: applications.x - 52, y: applications.y - 44)
let control = (x: (start.x + end.x) / 2, y: 32.0)
func arc(_ u: Double) -> (x: Double, y: Double) {
    let m = 1 - u
    return (m * m * start.x + 2 * m * u * control.x + u * u * end.x, m * m * start.y + 2 * m * u * control.y + u * u * end.y)
}
let arcPoints = (0...400).map { arc(Double($0) / 400) }
func nearestOnArc(_ x: Double, _ y: Double) -> (distance: Double, u: Double) {
    var best = Double.infinity, at = 0
    for (k, p) in arcPoints.enumerated() {
        let d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
        if d < best { best = d; at = k }
    }
    return (best.squareRoot(), Double(at) / 400)
}

// MARK: the cells

// Which cells take ink: the route, and the land, as dense as the icon's sea
// near the route and thinning toward the words above, the names below and
// the window's sides.
var inked = [Bool](repeating: false, count: columns * rows)
for j in 0..<rows {
    for i in 0..<columns {
        let x = Double(i) * cell, y = Double(j) * cell
        let cx = x + cell / 2, cy = y + cell / 2
        let near = nearestOnArc(cx, cy)
        // Thin where it sets out, as light setting out.
        var on = near.distance <= (near.u < 0.3 ? 1.1 : 2.1)
        if !on, near.distance > 6, isLandCell(x, y) {
            let presence = smoothstep(50, 92, cy) * (1 - smoothstep(app.y + 30, names - 16, cy))
                * smoothstep(0, 60, cx) * (1 - smoothstep(width - 60, width, cx))
            let tone = presence * (0.3 + 0.3 * exp(-near.distance / 120))
            on = tone > threshold(i, j)
        }
        inked[j * columns + i] = on
    }
}

// MARK: drawing

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func render(_ s: Double) -> CGImage {
    let c = CGContext(data: nil, width: Int(width * s), height: Int(height * s), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: height * s)
    c.scaleBy(x: s, y: -s)  // points, y down
    c.setShouldAntialias(false)
    c.setFillColor(paper)
    c.fill(CGRect(x: 0, y: 0, width: width, height: height))
    c.setFillColor(ink)
    for j in 0..<rows {
        for i in 0..<columns where inked[j * columns + i] {
            c.fill(CGRect(x: Double(i) * cell, y: Double(j) * cell, width: cell, height: cell))
        }
    }

    // One line.
    c.setShouldAntialias(true)
    let base = CTFontCreateUIFontForLanguage(.system, 10, nil)!
    let font = CTFontCreateCopyWithAttributes(base, 10, nil, CTFontDescriptorCreateWithAttributes(
        [kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23] as CFDictionary] as CFDictionary))
    let tracking = 2.0
    let words = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "LIGHTWEIGHT NETWORK TOPOLOGY MONITOR" as CFString, [
        kCTFontAttributeName: font, kCTForegroundColorAttributeName: muted, kCTKernAttributeName: tracking,
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
