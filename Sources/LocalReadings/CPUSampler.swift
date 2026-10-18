import Darwin
import Foundation

/// One logical core's tick counters, as `host_processor_info` reports them.
public struct CPUTicks: Sendable, Hashable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// CPU use between two readings of every core. The counters are 32-bit
    /// and wrap; a wrapped counter still gives the right delta. `nil` when
    /// the core count changed or no time passed.
    public static func usage(from old: [CPUTicks], to new: [CPUTicks]) -> CPUReading? {
        guard !new.isEmpty, old.count == new.count else { return nil }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        for (a, b) in zip(old, new) {
            user += UInt64(b.user &- a.user) + UInt64(b.nice &- a.nice)
            system += UInt64(b.system &- a.system)
            idle += UInt64(b.idle &- a.idle)
        }
        let all = user + system + idle
        guard all > 0 else { return nil }
        let u = Double(user) / Double(all) * 100
        let s = Double(system) / Double(all) * 100
        return CPUReading(total: min(100, u + s), system: s, user: u, logicalCores: new.count)
    }
}

/// CPU use from `host_processor_info` tick deltas.
public struct CPUSampler: Sampler {
    private var previous: [CPUTicks]?

    public init() {}

    public mutating func sample(at date: Date) -> CPUReading? {
        guard let now = Self.read() else { return nil }
        defer { previous = now }
        guard let previous else { return nil }
        return CPUTicks.usage(from: previous, to: now)
    }

    static func read() -> [CPUTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        guard Int(infoCount) >= Int(count) * states else { return nil }
        var out: [CPUTicks] = []
        out.reserveCapacity(Int(count))
        for cpu in 0..<Int(count) {
            let base = cpu * states
            func tick(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[base + Int(state)]) }
            out.append(CPUTicks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                                idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE)))
        }
        return out
    }
}
