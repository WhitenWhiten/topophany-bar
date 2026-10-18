import Darwin
import Foundation

extension MemoryReading {
    /// Activity Monitor's categories from one `HOST_VM_INFO64` reading.
    /// - App: anonymous pages less purgeable ones.
    /// - Wired: pages the kernel keeps in memory.
    /// - Compressed: pages the compressor occupies.
    public static func categories(_ vm: vm_statistics64, pageSize: UInt64, totalBytes: UInt64,
                                  memorystatusLevel: Int32?) -> MemoryReading {
        let internalPages = UInt64(vm.internal_page_count)
        let purgeable = UInt64(vm.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize
        let wired = UInt64(vm.wire_count) * pageSize
        let compressed = UInt64(vm.compressor_page_count) * pageSize
        let used = app + wired + compressed
        let percent = totalBytes > 0 ? min(100, Double(used) / Double(totalBytes) * 100) : 0
        let pressure = memorystatusLevel.flatMap { (0...100).contains($0) ? Double(100 - $0) : nil }
        return MemoryReading(totalBytes: totalBytes, appBytes: app, wiredBytes: wired, compressedBytes: compressed,
                             usedBytes: used, usedPercent: percent, pressurePercent: pressure)
    }
}

/// Memory from `host_statistics64` and `kern.memorystatus_level`.
public struct MemorySampler: Sampler {
    public init() {}

    public mutating func sample(at date: Date) -> MemoryReading? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        var page: vm_size_t = 0
        guard host_page_size(host, &page) == KERN_SUCCESS, page > 0 else { return nil }
        guard let total: UInt64 = SysctlValue.read("hw.memsize"), total > 0 else { return nil }
        let level: Int32? = SysctlValue.read("kern.memorystatus_level")
        return .categories(vm, pageSize: UInt64(page), totalBytes: total, memorystatusLevel: level)
    }
}

enum SysctlValue {
    /// A fixed-size integer sysctl.
    static func read<T: FixedWidthInteger>(_ name: String) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, size == MemoryLayout<T>.size else { return nil }
        return value
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        let s = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return s.isEmpty ? nil : s
    }
}
