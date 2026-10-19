import Foundation
import LocalReadings
import Testing
@testable import TopophanySections
import TopophanyEngine
import TopophanyKit

@Suite struct StatusItemModelTests {
    init() { L10n.force("en") }

    func item(_ status: StatusSection, readings: [Settings.Appearance.MenuBar.Reading] = [], local: LocalSnapshot? = nil)
        -> StatusItemModel {
        var a = Settings.Appearance.MenuBar()
        a.readings = readings
        return StatusItemModel(status: status, appearance: a, local: local)
    }

    func blind(_ engine: EngineCondition) -> StatusSection {
        SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: origin), engine: engine, settings: settings())).status
    }

    /// Only a current verdict may turn; `topo` starting, or about to start
    /// again, is under way; anything else rests.
    @Test func activity() {
        #expect(item(panel(.clear).status).activity == .live)
        #expect(item(panel(.incidents).status).activity == .live)
        #expect(item(panel(.incomplete).status).activity == .live)
        #expect(item(panel(.offline).status).activity == .resting)
        #expect(item(blind(.starting)).activity == .connecting)
        #expect(item(blind(.restarting(at: origin.addingTimeInterval(5)))).activity == .connecting)
        #expect(item(blind(.stopped)).activity == .resting)
        #expect(item(blind(.notFound)).activity == .resting)
        #expect(item(panel(.clear).status).motion)
    }

    /// Readings in their own order, unknown until sampled, never zero.
    @Test func readings() {
        let gb = 1e9
        let sample = LocalSample(
            at: origin,
            cpu: CPUReading(total: 16.8, system: 5.2, user: 11.6, logicalCores: 14),
            memory: MemoryReading(totalBytes: UInt64(24 * gb), appBytes: 0, wiredBytes: 0, compressedBytes: 0,
                                  usedBytes: UInt64(17.4 * gb), usedPercent: 72.4, pressurePercent: nil),
            network: NetworkReading(interface: "en0", displayName: "Wi-Fi", address: nil, receivedPerSecond: 1_400_000,
                                    sentPerSecond: 343_900))
        let local = LocalSnapshot(machine: MachineInfo(model: "MacBook Pro", chip: "", hasBattery: true), latest: sample,
                                  cpuHistory: [10, 20, 16.8], receivedHistory: [], sentHistory: [])
        let m = item(panel(.incidents).status, readings: [.cpu, .memory, .network], local: local)
        #expect(m.readings.map(\.kind) == [.cpu, .memory, .network])
        #expect(m.readings.map(\.value) == ["17%", "72%", "–"])
        #expect(m.readings[0].history == [0.1, 0.2, 0.168])
        #expect(m.readings[2].receivedText == "1.4 MB/s")
        #expect(m.readings[2].sentText == "344 kB/s")
        #expect(m.accessibilityLabel == """
            Topophany: 5 incidents, updated 4 seconds ago
            This Mac: CPU 17%, memory 72%, network 1.4 MB/s in, 344 kB/s out
            """)
        let none = item(panel(.incidents).status, readings: [.cpu, .network])
        #expect(none.readings.map(\.value) == ["–", "–"])
        #expect(none.readings[0].fraction == nil && none.readings[0].history.isEmpty)
        #expect(none.readings[1].receivedText == "–")
        #expect(none.readings.map(\.spoken) == ["CPU no reading", "network no reading"])
    }

    /// Only a change that needs more attention ripples: a worse mark, or
    /// more needing attention under the same one.
    @Test func moreAttention() {
        let clear = item(panel(.clear).status)
        let degraded = item(panel(.degraded).status)
        let incidents = item(panel(.incidents).status)
        let incomplete = item(panel(.incomplete).status)
        #expect(degraded.needsMoreAttention(than: clear))
        #expect(incidents.needsMoreAttention(than: degraded))
        #expect(degraded.needsMoreAttention(than: incomplete))
        #expect(!clear.needsMoreAttention(than: incidents))
        #expect(!degraded.needsMoreAttention(than: incidents))
        #expect(!incomplete.needsMoreAttention(than: clear))
        var fewer = incidents
        fewer.count = 3
        #expect(incidents.needsMoreAttention(than: fewer))
        #expect(!fewer.needsMoreAttention(than: incidents))
        #expect(!incidents.needsMoreAttention(than: incidents))
    }

    /// Rates in the menu bar's room: whole units from 100, one decimal
    /// under it, the next unit from 999.5.
    @Test func shortRates() {
        #expect(Words.shortRate(0) == "0 B/s")
        #expect(Words.shortRate(-3) == "0 B/s")
        #expect(Words.shortRate(999) == "999 B/s")
        #expect(Words.shortRate(999.6) == "1 kB/s")
        #expect(Words.shortRate(1500) == "1.5 kB/s")
        #expect(Words.shortRate(343_900) == "344 kB/s")
        #expect(Words.shortRate(1_400_000) == "1.4 MB/s")
        #expect(Words.shortRate(88_840_000) == "88.8 MB/s")
    }
}
