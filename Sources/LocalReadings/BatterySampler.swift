import Foundation
#if canImport(IOKit)
import IOKit.ps
#endif

extension BatteryReading {
    /// A reading from one IOKit power source description. `nil` unless it
    /// describes a present internal battery.
    public init?(powerSource d: [String: Any]) {
        guard d["Type"] as? String == "InternalBattery", d["Is Present"] as? Bool ?? true,
              let current = (d["Current Capacity"] as? NSNumber)?.doubleValue,
              let max = (d["Max Capacity"] as? NSNumber)?.doubleValue, max > 0
        else { return nil }
        let percent = Int((current / max * 100).rounded())
        let charging = d["Is Charging"] as? Bool ?? false
        let onAC = d["Power Source State"] as? String == "AC Power"
        let charged = d["Is Charged"] as? Bool ?? false
        func minutes(_ key: String) -> Int? {
            guard let m = (d[key] as? NSNumber)?.intValue, m > 0 else { return nil }
            return m
        }
        let state: State
        let remaining: Int?
        if charged || (onAC && !charging && percent >= 100) {
            state = .charged
            remaining = nil
        } else if charging {
            state = .charging
            remaining = minutes("Time to Full Charge")
        } else if onAC {
            state = .onPower
            remaining = nil
        } else {
            state = .discharging
            remaining = minutes("Time to Empty")
        }
        self.init(percent: Swift.max(0, Swift.min(100, percent)), state: state, minutesRemaining: remaining)
    }
}

/// The internal battery, from IOKit's power sources. `nil` on a Mac
/// without one.
public struct BatterySampler: Sampler {
    public init() {}

    public mutating func sample(at date: Date) -> BatteryReading? {
        Self.descriptions().lazy.compactMap(BatteryReading.init(powerSource:)).first
    }

    static var present: Bool { descriptions().contains { BatteryReading(powerSource: $0) != nil } }

    static func descriptions() -> [[String: Any]] {
        #if canImport(IOKit)
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        return list.compactMap { ps in
            IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any]
        }
        #else
        return []
        #endif
    }
}
