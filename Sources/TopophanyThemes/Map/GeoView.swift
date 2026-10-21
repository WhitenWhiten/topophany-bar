import CoreGraphics
import Foundation
import TopophanySections

/// The geo map's projection, as `topo`'s geo map frames it
/// (internal/tui/geo.go): equirectangular, its horizontal scale
/// cos(centre latitude) so a mid-latitude network keeps its shape.
/// Longitudes lon0+x0 … lon0+x1 and latitudes lo … hi exist on the map; a
/// map wider than the world shows it once, centred, and spare height is
/// left empty rather than filled with Antarctica. Folds squeeze wide
/// stretches of empty longitude, such as an ocean between two coasts, into
/// narrow seams.
///
/// Units are the map's: x across, y down, `ky` times as tall as they are
/// wide (points, where ky is 1; a terminal's braille dots, where it isn't).
struct GeoView: Sendable, Hashable {
    /// Squeezes the degrees a ≤ d < b east of lon0 into `seam` degrees.
    struct Fold: Sendable, Hashable {
        var a, b, seam: Double
    }

    var lon0, lat0, scale, kx, ky, x0, x1, lo, hi: Double
    var folds: [Fold] = []

    // Gaps between sites wider than foldGap degrees of longitude are
    // folded, keeping foldPad degrees beside each site and a seam foldSeam
    // degrees wide.
    static let foldGap = 60.0, foldPad = 15.0, foldSeam = 6.0

    /// Degrees east of lon0 to degrees across the map.
    func squeeze(_ d: Double) -> Double {
        var out = d
        for f in folds {
            if d >= f.b {
                out -= f.b - f.a - f.seam
            } else if d > f.a {
                out -= (d - f.a) * (1 - f.seam / (f.b - f.a))
            }
        }
        return out
    }

    func unsqueeze(_ s: Double) -> Double {
        var shift = 0.0
        for f in folds {
            let a = f.a - shift
            if s >= a + f.seam {
                shift += f.b - f.a - f.seam
            } else if s > a {
                return f.a + (s - a) * (f.b - f.a) / f.seam
            } else {
                return s + shift
            }
        }
        return s + shift
    }

    func project(_ lat: Double, _ lon: Double) -> CGPoint {
        var d = (lon - lon0 - x0).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return CGPoint(x: squeeze(d + x0) * kx / scale, y: (lat0 - lat) / scale / ky)
    }

    func project(_ c: MapSection.Coordinate) -> CGPoint { project(c.lat, c.lon) }

    /// The inverse of `project`; nil off the world and in a fold's seam,
    /// which is left blank.
    func at(_ px: Double, _ py: Double) -> (lat: Double, lon: Double)? {
        let s = px * scale / kx
        let lat = lat0 - py * ky * scale
        for f in folds {
            let a = squeeze(f.a)
            if s > a && s < a + f.seam { return nil }
        }
        let d = unsqueeze(s)
        guard d >= x0, d < x1, lat >= lo, lat <= hi else { return nil }
        return (lat, lon0 + d)
    }

    /// Each fold's seam: where it runs across the map, and how many degrees
    /// of longitude it holds.
    var seams: [(x: Double, degrees: Int)] {
        folds.map { ((squeeze($0.a) + $0.seam / 2) * kx / scale, Int(($0.b - $0.a).rounded())) }
    }

    /// The smallest arc of longitude holding every point, so Shanghai and
    /// Los Angeles span the Pacific rather than Europe.
    static func lonBounds(_ lons: [Double]) -> (centre: Double, span: Double) {
        let ls = lons.map { (($0.truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360) - 180 }.sorted()
        guard let first = ls.first, let last = ls.last else { return (0, 0) }
        var gap = 360 - (last - first), start = first
        for i in 1..<ls.count where ls[i] - ls[i - 1] > gap {
            gap = ls[i] - ls[i - 1]
            start = ls[i]
        }
        let span = 360 - gap
        return (start + span / 2, span)
    }

    /// Frames a `width` × `height` map: `fit` fits every point, folding
    /// wide gaps between them so the places get the width; `world` shows
    /// the world centred on them. Antarctica is left out unless a point is
    /// there, and the frame never zooms out past one world.
    static func framing(_ points: [MapSection.Coordinate], width wd: Double, height: Double, ky: Double = 1,
                        frame: MapSection.Frame) -> GeoView {
        framing(points, wd, height, ky, frame, folding: frame == .fit)
    }

    private static func framing(_ points: [MapSection.Coordinate], _ wd: Double, _ height: Double, _ ky: Double,
                                _ frame: MapSection.Frame, folding: Bool) -> GeoView {
        let hd = height * ky  // in widths from here on
        var lo = -56.0, hi = 80.0
        for p in points {
            lo = min(lo, p.lat - 10)
            hi = max(hi, p.lat + 10)
        }
        lo = max(lo, -90)
        hi = min(hi, 90)
        var cLat = (lo + hi) / 2, cLon = 10.0
        var spanLat = hi - lo, spanLon = 360.0
        var folds: [Fold] = []
        var removed = 0.0, lead = 0.0
        if !points.isEmpty {
            var span: Double
            (cLon, span) = lonBounds(points.map(\.lon))
            let minLat = points.map(\.lat).min() ?? 0, maxLat = points.map(\.lat).max() ?? 0
            if folding {
                // Degrees east of the points' western end, where each gap
                // starts and ends.
                let west = cLon - span / 2
                let ds = points.map { p -> Double in
                    let d = (p.lon - west + 1e-9).truncatingRemainder(dividingBy: 360)
                    return (d + 360).truncatingRemainder(dividingBy: 360)
                }.sorted()
                for i in 1..<max(1, ds.count) {
                    let a = ds[i - 1] + foldPad, b = ds[i] - foldPad
                    if ds[i] - ds[i - 1] > foldGap && b - a > 2 * foldSeam {
                        folds.append(Fold(a: a, b: b, seam: foldSeam))
                        removed += b - a - foldSeam
                    }
                }
                span -= removed
                cLon = west + span / 2  // in degrees across the map from here on
            }
            if frame == .fit {
                cLat = (minLat + maxLat) / 2
                spanLon = max(span + max(32, span * 0.2), 64)
                spanLat = max(maxLat - minLat + max(22, (maxLat - minLat) * 0.35), 32)
            }
            lead = span / 2
        }
        let kx = min(1, max(0.62, cos(cLat * .pi / 180)))
        let whole = max(360 * kx / wd, (hi - lo) / hd)
        let scale = min(max(spanLon * kx / wd, spanLat / hd), whole)
        let vs = hd * scale
        cLat = vs >= hi - lo ? (lo + hi) / 2 : min(max(cLat, lo + vs / 2), hi - vs / 2)
        let hs = wd * scale / kx
        var g = GeoView(lon0: cLon - hs / 2, lat0: cLat + vs / 2, scale: scale, kx: kx, ky: ky, x0: 0, x1: hs, lo: lo, hi: hi)
        if !folds.isEmpty {
            // The whole world fits: nothing needs folding.
            if hs >= 360 - removed { return framing(points, wd, height, ky, frame, folding: false) }
            // The points' western end stands hs/2 - lead east of lon0.
            g.folds = folds.map { Fold(a: $0.a + hs / 2 - lead, b: $0.b + hs / 2 - lead, seam: $0.seam) }
            g.x1 = g.unsqueeze(hs)
            return g
        }
        if hs > 360 {
            g.x0 = (hs - 360) / 2
            g.x1 = (hs + 360) / 2
        }
        return g
    }
}
