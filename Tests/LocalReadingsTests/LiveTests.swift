import Foundation
import Testing
@testable import LocalReadings

/// Samples this Mac. Ranges only: the values themselves are the machine's.
@Suite struct LiveTests {
    @Test func cpu() async throws {
        var s = CPUSampler()
        #expect(s.sample(at: Date()) == nil)
        try await Task.sleep(for: .milliseconds(300))
        let sampled = s.sample(at: Date())
        let r = try #require(sampled)
        #expect((0...100).contains(r.total))
        #expect(r.system >= 0 && r.user >= 0)
        #expect(abs(r.total - min(100, r.system + r.user)) < 1e-9)
        #expect(r.logicalCores > 0)
    }

    @Test func memory() throws {
        var s = MemorySampler()
        let sampled = s.sample(at: Date())
        let m = try #require(sampled)
        #expect(m.totalBytes > 0)
        #expect(m.usedBytes == m.appBytes + m.wiredBytes + m.compressedBytes)
        #expect(m.usedBytes <= m.totalBytes)
        #expect((0...100).contains(m.usedPercent))
        if let p = m.pressurePercent { #expect((0...100).contains(p)) }
    }

    @Test func startupVolume() throws {
        var s = StorageSampler()
        let sampled = s.sample(at: Date())
        let v = try #require(sampled)
        #expect(v.totalBytes > 0)
        #expect(v.usedBytes + v.availableBytes == v.totalBytes)
        #expect((0...100).contains(v.usedPercent))
        #expect(!StorageSampler.volumes().isEmpty)
    }

    @Test func network() async throws {
        let names = NetworkSampler.activeInterfaces()
        guard let name = names.first(where: { $0.hasPrefix("en") }) else { return }
        #expect(!NetworkSampler.counters().isEmpty)
        var s = NetworkSampler(interface: name)
        #expect(s.sample(at: Date()) == nil)
        try await Task.sleep(for: .milliseconds(300))
        let sampled = s.sample(at: Date())
        let r = try #require(sampled)
        #expect(r.receivedPerSecond >= 0 && r.sentPerSecond >= 0)
        #expect(r.interface == name)
    }

    @Test func battery() {
        var s = BatterySampler()
        guard let b = s.sample(at: Date()) else { return }
        #expect((0...100).contains(b.percent))
        if let m = b.minutesRemaining { #expect(m > 0) }
    }

    @Test func machine() {
        let m = MachineInfo.current()
        #expect(!m.model.isEmpty)
        #expect(!m.model.contains("("))
    }

    @Test func monitorStreamsSnapshots() async throws {
        let monitor = LocalReadingsMonitor(configuration: .init(every: 1))
        var seen: [LocalSnapshot] = []
        for await snap in monitor.snapshots() {
            seen.append(snap)
            if seen.count == 2 { break }
        }
        let first = try #require(seen.first)
        #expect(first.latest.cpu != nil)
        #expect(first.latest.memory != nil)
        #expect(first.latest.storage != nil)
        #expect(seen[1].cpuHistory.count == 2)
        #expect(seen[1].latest.at.timeIntervalSince(first.latest.at) >= 0.9)
        // A monitor starts once.
        var again = 0
        for await _ in monitor.snapshots() { again += 1 }
        #expect(again == 0)
    }

    @Test func onlyRequestedKinds() async throws {
        let monitor = LocalReadingsMonitor(configuration: .init(kinds: [.memory], every: 1))
        var first: LocalSnapshot?
        for await snap in monitor.snapshots() {
            first = snap
            break
        }
        let s = try #require(first)
        #expect(s.latest.memory != nil)
        #expect(s.latest.cpu == nil && s.latest.network == nil && s.latest.storage == nil && s.latest.battery == nil)
    }
}
