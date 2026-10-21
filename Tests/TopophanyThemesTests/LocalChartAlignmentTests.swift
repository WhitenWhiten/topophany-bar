import CoreGraphics
import LocalReadings
import SwiftUI
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor
@Suite(.serialized) struct LocalChartAlignmentTests {
    /// Compare the coloured shapes in real tiles, including their headers,
    /// graph frames and footers. A baseline at the centre still leaves a
    /// bottom-aligned CPU column visibly above the memory meter.
    @Test func columnCentresMatchMemory() throws {
        let ctx = RenderContext(theme: ThemeStore.native, colorScheme: .light)
        let p = CardsPalette.resolve(ctx)
        let local = CardsLocal(local: .init(model: "Mac", readings: [], snapshot: nil), p: p, t: CardsType(scale: 1))
        for style in [MeterStyle.ticks, .rule, .dots] {
            for value in [0.0, 12, 100] {
                let row = HStack(spacing: 5) {
                    local.tile("cpu", "CPU", "12.0%",
                               BarHistory(values: Array(repeating: value, count: 60), top: max(25, value * 1.2), capacity: 60,
                                          color: Color(red: 1, green: 0, blue: 0), baseline: .clear, style: style), "System 4.0% · User 8.0%")
                    local.tile("memorychip", "Memory", "56.0%",
                               PartsBar(parts: [(56, Color(red: 0, green: 0, blue: 1))], total: 100, track: .clear, style: style),
                               "Pressure 30% · App 6.4 GB")
                }
                .frame(width: 304)
                .background(Color.white)
                let renderer = ImageRenderer(content: row)
                renderer.scale = 4
                let image = try #require(renderer.cgImage)
                let cpu = try colourCentre(image, channel: 0)
                let memory = try colourCentre(image, channel: 2)
                // The rule meter's coloured band sits 0.975 pt below its
                // frame centre; ticks and dots must agree within one pixel.
                let tolerance = style == .rule ? 4.0 : 1.0
                #expect(abs(cpu - memory) <= tolerance, "\(style) \(value)%: CPU \(cpu), memory \(memory)")
            }
        }
    }

    @Test func localCardSnapshots() throws {
        L10n.force("en")
        var sample = sampleLocal
        sample.machine = MachineInfo(model: "Mac", chip: "", hasBattery: false)
        sample.latest.cpu = CPUReading(total: 12, system: 4, user: 8, logicalCores: 8)
        sample.cpuHistory = Array(repeating: 12, count: 60)
        sample.latest.memory?.usedPercent = 56
        sample.latest.battery = nil
        let local = LocalSection(model: "Mac", readings: [.cpu, .memory, .storage, .network], snapshot: sample)
        for theme in ThemeStore.builtIn where theme.renderer == .cards {
            for dark in [true, false] where theme.appearance == .system || (theme.appearance == .dark) == dark {
                let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
                try snapshot("local-chart-centres-\(theme.id)-\(dark ? "dark" : "light")",
                             CardsLocal(local: local, p: CardsPalette.resolve(ctx), t: CardsType(scale: 1, theme: theme))
                                .frame(width: 328).padding(8).background(dark ? Color.black : Color.white))
            }
        }
    }

    private func colourCentre(_ image: CGImage, channel: Int) throws -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let ctx = try #require(CGContext(data: bytes.baseAddress, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var rows: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if pixels[i + channel] > 180 && pixels[i + 1] < 80 && pixels[i + (2 - channel)] < 80 {
                    rows.append(y)
                    break
                }
            }
        }
        return Double(try #require(rows.first) + (try #require(rows.last))) / 2
    }
}
