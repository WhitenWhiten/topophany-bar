import SwiftUI
import Testing
@testable import TopophanyThemes

/// The mark at the sizes widgets and the panel draw it, and large, to
/// compare with design/assets/mark.svg.
@MainActor
@Suite struct BrandMarkSnapshots {
    @Test func markAtEverySize() throws {
        let sizes = [18.0, 26, 64, 256]
        for dark in [false, true] {
            let size = try snapshot("mark-\(dark ? "dark" : "light")", HStack(spacing: 16) {
                ForEach(sizes, id: \.self) { s in BrandMark().frame(width: s, height: s) }
            }
            .padding(16)
            .background(dark ? Color(rgb: 0x202124) : Color(rgb: 0xF1F3F4)))
            #expect(size == CGSize(width: sizes.reduce(0, +) + 16 * Double(sizes.count + 1), height: 256 + 32))
        }
    }
}
