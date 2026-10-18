import Darwin
import Foundation
import Testing
@testable import LocalReadings

@Suite struct CPUTickTests {
    @Test func usageFromDeltas() throws {
        let old = [CPUTicks(user: 100, system: 50, idle: 800, nice: 0), CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let new = [CPUTicks(user: 130, system: 60, idle: 860, nice: 0), CPUTicks(user: 10, system: 10, idle: 70, nice: 10)]
        // Deltas: user 30+20 (nice 10 counted as user), system 10+10, idle 60+70: 50 + 20 + 130 = 200.
        let r = try #require(CPUTicks.usage(from: old, to: new))
        #expect(abs(r.user - 25) < 1e-9)
        #expect(abs(r.system - 10) < 1e-9)
        #expect(abs(r.total - 35) < 1e-9)
        #expect(r.logicalCores == 2)
    }

    @Test func wrappedCountersStillGiveTheDelta() throws {
        let old = [CPUTicks(user: UInt32.max - 9, system: UInt32.max, idle: UInt32.max - 49, nice: 0)]
        let new = [CPUTicks(user: 10, system: 9, idle: 50, nice: 0)]
        // user +20, system +10, idle +100.
        let r = try #require(CPUTicks.usage(from: old, to: new))
        #expect(abs(r.user - 20.0 / 130 * 100) < 1e-9)
        #expect(abs(r.system - 10.0 / 130 * 100) < 1e-9)
    }

    @Test func noTimeOrChangedCoresIsNil() {
        let a = [CPUTicks(user: 1, system: 1, idle: 1, nice: 1)]
        #expect(CPUTicks.usage(from: a, to: a) == nil)
        #expect(CPUTicks.usage(from: a, to: a + a) == nil)
        #expect(CPUTicks.usage(from: [], to: []) == nil)
    }
}

@Suite struct NetworkRateTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func bytesPerSecond() throws {
        let a = InterfaceCounters(interface: "en0", received: 1_000, sent: 500, at: t0)
        let b = InterfaceCounters(interface: "en0", received: 5_000, sent: 1_500, at: t0.addingTimeInterval(2))
        let r = try #require(b.rates(since: a))
        #expect(r.received == 2_000)
        #expect(r.sent == 500)
    }

    @Test func counterResetStartsOver() {
        let a = InterfaceCounters(interface: "en0", received: 9_000, sent: 500, at: t0)
        let b = InterfaceCounters(interface: "en0", received: 100, sent: 600, at: t0.addingTimeInterval(2))
        #expect(b.rates(since: a) == nil)
    }

    @Test func otherInterfaceOrNoTimeIsNil() {
        let a = InterfaceCounters(interface: "en0", received: 1, sent: 1, at: t0)
        #expect(InterfaceCounters(interface: "en1", received: 2, sent: 2, at: t0.addingTimeInterval(1)).rates(since: a) == nil)
        #expect(InterfaceCounters(interface: "en0", received: 2, sent: 2, at: t0).rates(since: a) == nil)
    }
}

@Suite struct MemoryCategoryTests {
    @Test func activityMonitorCategories() {
        var vm = vm_statistics64()
        vm.internal_page_count = 1_000
        vm.purgeable_count = 200
        vm.wire_count = 300
        vm.compressor_page_count = 100
        vm.free_count = 5_000
        let page: UInt64 = 16_384
        let total: UInt64 = 4_000 * page
        let m = MemoryReading.categories(vm, pageSize: page, totalBytes: total, memorystatusLevel: 62)
        #expect(m.appBytes == 800 * page)
        #expect(m.wiredBytes == 300 * page)
        #expect(m.compressedBytes == 100 * page)
        #expect(m.usedBytes == 1_200 * page)
        #expect(abs(m.usedPercent - 30) < 1e-9)
        #expect(m.pressurePercent == 38)
        #expect(m.totalBytes == total)
    }

    @Test func purgeableBeyondInternalIsNoApp() {
        var vm = vm_statistics64()
        vm.internal_page_count = 10
        vm.purgeable_count = 20
        let m = MemoryReading.categories(vm, pageSize: 4_096, totalBytes: 1 << 30, memorystatusLevel: nil)
        #expect(m.appBytes == 0)
        #expect(m.pressurePercent == nil)
    }

    @Test func implausibleLevelIsUnknown() {
        let m = MemoryReading.categories(vm_statistics64(), pageSize: 4_096, totalBytes: 1 << 30, memorystatusLevel: 140)
        #expect(m.pressurePercent == nil)
    }
}

@Suite struct BatteryParsingTests {
    let base: [String: Any] = ["Type": "InternalBattery", "Is Present": true, "Current Capacity": 82, "Max Capacity": 100]

    func with(_ extra: [String: Any]) -> [String: Any] { base.merging(extra) { $1 } }

    @Test func charging() throws {
        let b = try #require(BatteryReading(powerSource: with([
            "Is Charging": true, "Power Source State": "AC Power", "Time to Full Charge": 72,
        ])))
        #expect(b == BatteryReading(percent: 82, state: .charging, minutesRemaining: 72))
    }

    @Test func dischargingWhileEstimating() throws {
        let b = try #require(BatteryReading(powerSource: with([
            "Is Charging": false, "Power Source State": "Battery Power", "Time to Empty": -1,
        ])))
        #expect(b == BatteryReading(percent: 82, state: .discharging, minutesRemaining: nil))
    }

    @Test func discharging() throws {
        let b = try #require(BatteryReading(powerSource: with([
            "Is Charging": false, "Power Source State": "Battery Power", "Time to Empty": 254,
        ])))
        #expect(b.minutesRemaining == 254)
    }

    @Test func chargedAndHeldOnPower() throws {
        let full = try #require(BatteryReading(powerSource: with([
            "Current Capacity": 100, "Is Charging": false, "Is Charged": true, "Power Source State": "AC Power",
        ])))
        #expect(full.state == .charged)
        let held = try #require(BatteryReading(powerSource: with([
            "Is Charging": false, "Power Source State": "AC Power",
        ])))
        #expect(held.state == .onPower)
        #expect(held.minutesRemaining == nil)
    }

    @Test func notABattery() {
        #expect(BatteryReading(powerSource: ["Type": "UPS", "Current Capacity": 50, "Max Capacity": 100]) == nil)
        #expect(BatteryReading(powerSource: with(["Is Present": false])) == nil)
        #expect(BatteryReading(powerSource: with(["Max Capacity": 0])) == nil)
    }
}

@Suite struct StorageAndNamesTests {
    @Test func usedFromAvailable() {
        let s = StorageSampler.reading(name: "Macintosh HD", path: "/", total: 1_000, available: 250)
        #expect(s.usedBytes == 750)
        #expect(s.usedPercent == 75)
        // Purgeable space can make "available" exceed what's free; never below zero used.
        let over = StorageSampler.reading(name: "X", path: "/", total: 1_000, available: 1_200)
        #expect(over.usedBytes == 0)
    }

    @Test func marketingNames() {
        #expect(MachineInfo.trimmed("MacBook Pro (14-inch, Nov 2024)") == "MacBook Pro")
        #expect(MachineInfo.trimmed("Mac mini") == "Mac mini")
        #expect(MachineInfo.familyName("MacBookPro18,3") == "MacBook Pro")
        #expect(MachineInfo.familyName("MacBookAir10,1") == "MacBook Air")
        #expect(MachineInfo.familyName("Macmini9,1") == "Mac mini")
        #expect(MachineInfo.familyName("Mac16,7") == "Mac")
    }

    @Test func intervalsRoundTrip() {
        #expect(Set(LocalReadingKind.allCases.map(\.rawValue)) == ["cpu", "memory", "storage", "network", "battery"])
    }
}
