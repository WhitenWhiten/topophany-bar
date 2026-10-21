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
        var l = (lon + 180).truncatingRemainder(dividingBy: 360)
        if l < 0 { l += 360 }
        let col = min(width - 1, Int(l * 2))
        let row = min(height - 1, max(0, Int((90 - lat) * 2)))
        let i = row * width + col
        return i >> 3 < bits.count && bits[i >> 3] & (0x80 >> UInt8(i & 7)) != 0
    }
}
