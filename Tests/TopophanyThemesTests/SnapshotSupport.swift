import Foundation
import ImageIO
import LocalReadings
import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes
import UniformTypeIdentifiers

/// Where snapshot PNGs go: Tests/Snapshots/out (ignored by git).
let snapshotDirectory: URL = {
    let here = URL(filePath: #filePath)
    let dir = here.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Snapshots/out")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

/// Renders a view to a PNG at 2x and returns its size in points.
@MainActor
@discardableResult
func snapshot(_ name: String, scale: Double = 2, _ view: some View) throws -> CGSize {
    let r = ImageRenderer(content: view)
    r.scale = scale
    let image = try #require(r.cgImage, "nothing rendered for \(name)")
    let url = snapshotDirectory.appending(path: name + ".png")
    let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    #expect(CGImageDestinationFinalize(dest))
    return CGSize(width: Double(image.width) / scale, height: Double(image.height) / scale)
}

/// The desktop behind the previews' panels: soft blobs of color.
struct Wallpaper: View {
    var dark: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: dark ? [Color(rgb: 0x0E1528), Color(rgb: 0x0A0F1D), Color(rgb: 0x0B1222)]
                                            : [Color(rgb: 0xEAF0FB), Color(rgb: 0xF6F1FA)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                blob(dark ? RGBA(58 / 255, 104 / 255, 196 / 255, 0.62) : RGBA(120 / 255, 170 / 255, 1, 0.7), 0.16, 0.2, w, h)
                blob(dark ? RGBA(132 / 255, 74 / 255, 196 / 255, 0.5) : RGBA(206 / 255, 160 / 255, 1, 0.62), 0.86, 0.14, w, h)
                blob(dark ? RGBA(18 / 255, 146 / 255, 134 / 255, 0.48) : RGBA(110 / 255, 226 / 255, 204 / 255, 0.58), 0.74, 0.84, w, h)
                blob(dark ? RGBA(196 / 255, 72 / 255, 124 / 255, 0.38) : RGBA(1, 168 / 255, 200 / 255, 0.55), 0.18, 0.88, w, h)
            }
        }
    }

    func blob(_ c: RGBA, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [Color(c), Color(c).opacity(0)], center: .center, startRadius: 0, endRadius: 0.6 * max(w, h) * 0.7))
            .frame(width: 1.2 * w, height: 0.9 * h)
            .position(x: x * w, y: y * h)
    }
}

/// A panel on the desktop, as the previews show it.
struct OnDesktop<Content: View>: View {
    var dark: Bool
    var padding = 24.0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Wallpaper(dark: dark))
    }
}

// MARK: fixtures

let snapshotOrigin = Timestamp.parse("2026-10-18T13:30:00Z")!

func previewSettings(mac: Sections.MacMode = .local, servers: Bool = false, limit: Int = 3) -> TopophanyKit.Settings {
    var s = TopophanyKit.Settings()
    s.sections.attentionLimit = limit
    s.sections.servers = servers
    s.sections.serverNodes = ["oracle-ny", "bwh-la"]
    s.sections.mac.mode = mac
    s.sections.mac.node = "macbook"
    return s
}

/// data.js's This Mac: a MacBook Pro with a battery, so every reading shows.
let sampleLocal: LocalSnapshot = {
    func series(_ seed: Double, _ n: Int, _ base: Double, _ swing: Double, _ floor: Double, _ ceil: Double) -> [Double] {
        var out: [Double] = []
        var v = base
        for i in 0..<n {
            let s = sin(seed * 12.9898 + Double(i) * 78.233) * 43758.5453
            let r = s - s.rounded(.down) - 0.5
            v += r * swing + (base - v) * 0.18
            out.append(max(floor, min(ceil, v)))
        }
        return out
    }
    let gb = 1e9
    let sample = LocalSample(
        at: snapshotOrigin,
        cpu: CPUReading(total: 16.8, system: 5.2, user: 11.6, logicalCores: 14),
        memory: MemoryReading(totalBytes: UInt64(24 * gb), appBytes: UInt64(5.5 * gb), wiredBytes: UInt64(3.5 * gb),
                              compressedBytes: UInt64(3.4 * gb), usedBytes: UInt64(17.4 * gb), usedPercent: 72.4,
                              pressurePercent: 40.2),
        storage: StorageReading(volumeName: "Macintosh HD", path: "/", totalBytes: Int64(245.1 * gb),
                                availableBytes: Int64(138 * gb), usedBytes: Int64(107.1 * gb), usedPercent: 43.7),
        network: NetworkReading(interface: "en0", displayName: "Wi-Fi", address: "192.168.31.116",
                                receivedPerSecond: 343_900, sentPerSecond: 329_500),
        battery: BatteryReading(percent: 82, state: .charging, minutesRemaining: 72))
    return LocalSnapshot(machine: MachineInfo(model: "MacBook Pro", chip: "Apple M4 Pro", hasBattery: true), latest: sample,
                         cpuHistory: series(3, 40, 17, 9, 4, 60), receivedHistory: series(11, 40, 45, 26, 4, 95),
                         sentHistory: series(7, 40, 30, 22, 2, 90))
}()

/// This Mac's zone in every snapshot: Seattle's, where data.js puts it.
let snapshotHere = TimeZone(identifier: "America/Los_Angeles")!

func previewPanel(_ scenario: FixtureEngine.Scenario, after: TimeInterval = 4, settings: TopophanyKit.Settings = previewSettings(),
                  engine: EngineCondition = .running) -> PanelModel {
    let request = TemplateCompiler().request(for: settings, revision: 1, listServers: true)
    let reading = FixtureEngine.reading(scenario, request: request, origin: snapshotOrigin, after: after)
    return SectionBuilder.panel(PanelInput(reading: reading, engine: engine, settings: settings, local: sampleLocal, here: snapshotHere))
}

let panelScenarios: [FixtureEngine.Scenario] = [.clear, .degraded, .incidents, .incomplete, .offline]
