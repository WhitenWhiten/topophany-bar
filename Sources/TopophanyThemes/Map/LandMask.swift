import Foundation

/// Where the land is: Natural Earth 1:110m land (public domain) in 0.5°
/// cells, row 0 at 90°N and column 0 at 180°W, the mask `topo`'s geo map
/// draws (design/assets/land.bin).
enum LandMask {
    static let width = 720, height = 360

    static let bits: [UInt8] = {
        guard let url = Bundle.module.url(forResource: "land", withExtension: "bin"),
              let d = try? Data(contentsOf: url), d.count == width * height / 8 else { return [] }
        return [UInt8](d)
    }()

    static func isLand(_ lat: Double, _ lon: Double) -> Bool {
        isLand(row: row(lat), column: column(lon))
    }

    static func column(_ lon: Double) -> Int {
        var l = (lon + 180).truncatingRemainder(dividingBy: 360)
        if l < 0 { l += 360 }
        return min(width - 1, Int(l * 2))
    }

    static func row(_ lat: Double) -> Int {
        min(height - 1, max(0, Int((90 - lat) * 2)))
    }

    static func isLand(row: Int, column: Int) -> Bool {
        let i = row * width + column
        return i >> 3 < bits.count && bits[i >> 3] & (0x80 >> UInt8(i & 7)) != 0
    }
}

/// The same n×n coast samples as GeoScene.land, with each sample's
/// projected latitude/longitude prepared once per row/column. During a
/// zoom this replaces tens of thousands of inverse projections per frame
/// with a few hundred, retaining every antialiasing sample and fold seam.
struct LandCoverage {
    private var width: Int
    private var values: [Double]

    init(scene: GeoScene, x: [Double], y: [Double], pitch: Double, samples: Int = 3) {
        let t = scene.transform
        let view = scene.view
        let sampleCount = Double(samples * samples)
        let columns: [[Int]] = x.map { center in
            (0..<samples).compactMap { index in
                let point = center - pitch / 2 + (Double(index) + 0.5) * pitch / Double(samples)
                return view.longitude(at: (point - t.offset.x) / t.zoom).map(LandMask.column)
            }
        }
        let rows: [[Int]] = y.map { center in
            (0..<samples).compactMap { index in
                let point = center - pitch / 2 + (Double(index) + 0.5) * pitch / Double(samples)
                return view.latitude(at: (point - t.offset.y) / t.zoom).map(LandMask.row)
            }
        }
        width = columns.count
        var values = [Double](repeating: 0, count: columns.count * rows.count)
        // The mask is either empty or a validated 720×360 bit plane.
        // Projected rows and columns are clamped to that plane. Borrow its
        // bytes once, keeping array access and static initialization checks
        // out of the nine-sample inner loop; the pointer never escapes.
        LandMask.bits.withUnsafeBufferPointer { bytes in
            guard bytes.count == LandMask.width * LandMask.height / 8, let bits = bytes.baseAddress else { return }
            for (row, ys) in rows.enumerated() {
                for (column, xs) in columns.enumerated() {
                    var hits = 0
                    for y in ys {
                        let start = y * LandMask.width
                        for x in xs {
                            let index = start + x
                            if bits[index >> 3] & (0x80 >> UInt8(index & 7)) != 0 { hits += 1 }
                        }
                    }
                    values[row * columns.count + column] = Double(hits) / sampleCount
                }
            }
        }
        self.values = values
    }

    func coverage(column: Int, row: Int) -> Double {
        values[row * width + column]
    }
}
