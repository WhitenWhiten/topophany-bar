import Foundation

// This Mac's own readings, read in-process from the kernel and IOKit. They
// are not evidence: they carry no health and are never sent anywhere.

public enum LocalReadingKind: String, Sendable, Hashable, CaseIterable {
    case cpu, memory, storage, network, battery
}

/// CPU use over the last interval, in percent of all logical cores.
public struct CPUReading: Sendable, Hashable {
    public var total: Double
    public var system: Double
    /// User time, nice included.
    public var user: Double
    public var logicalCores: Int

    public init(total: Double, system: Double, user: Double, logicalCores: Int) {
        self.total = total
        self.system = system
        self.user = user
        self.logicalCores = logicalCores
    }
}

/// Memory in Activity Monitor's categories.
public struct MemoryReading: Sendable, Hashable {
    public var totalBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    /// App + wired + compressed: Activity Monitor's "Memory Used".
    public var usedBytes: UInt64
    public var usedPercent: Double
    /// 100 − `kern.memorystatus_level`; `nil` when it can't be read.
    public var pressurePercent: Double?

    public init(totalBytes: UInt64, appBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, usedBytes: UInt64,
                usedPercent: Double, pressurePercent: Double?) {
        self.totalBytes = totalBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.usedBytes = usedBytes
        self.usedPercent = usedPercent
        self.pressurePercent = pressurePercent
    }
}

/// One volume. `availableBytes` is the capacity available for important
/// use, as Finder counts it.
public struct StorageReading: Sendable, Hashable {
    public var volumeName: String
    public var path: String
    public var totalBytes: Int64
    public var availableBytes: Int64
    public var usedBytes: Int64
    public var usedPercent: Double

    public init(volumeName: String, path: String, totalBytes: Int64, availableBytes: Int64, usedBytes: Int64,
                usedPercent: Double) {
        self.volumeName = volumeName
        self.path = path
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.usedBytes = usedBytes
        self.usedPercent = usedPercent
    }
}

/// Throughput of one interface, in bytes per second.
public struct NetworkReading: Sendable, Hashable {
    /// The BSD name, such as `en0`.
    public var interface: String
    /// "Wi-Fi", "Ethernet", or the BSD name.
    public var displayName: String
    /// The IPv4 address, else an IPv6 one.
    public var address: String?
    public var receivedPerSecond: Double
    public var sentPerSecond: Double

    public init(interface: String, displayName: String, address: String?, receivedPerSecond: Double,
                sentPerSecond: Double) {
        self.interface = interface
        self.displayName = displayName
        self.address = address
        self.receivedPerSecond = receivedPerSecond
        self.sentPerSecond = sentPerSecond
    }
}

public struct BatteryReading: Sendable, Hashable {
    public enum State: String, Sendable, Hashable {
        case charging, charged, discharging
        /// On power, not charging.
        case onPower
    }

    public var percent: Int
    public var state: State
    /// To full while charging, to empty while discharging; `nil` while the
    /// system is still estimating.
    public var minutesRemaining: Int?

    public init(percent: Int, state: State, minutesRemaining: Int?) {
        self.percent = percent
        self.state = state
        self.minutesRemaining = minutesRemaining
    }
}

public struct LocalSample: Sendable, Hashable {
    public var at: Date
    public var cpu: CPUReading?
    public var memory: MemoryReading?
    public var storage: StorageReading?
    public var network: NetworkReading?
    public var battery: BatteryReading?

    public init(at: Date, cpu: CPUReading? = nil, memory: MemoryReading? = nil, storage: StorageReading? = nil,
                network: NetworkReading? = nil, battery: BatteryReading? = nil) {
        self.at = at
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.network = network
        self.battery = battery
    }
}

/// The latest sample with a minute of history for the sparklines.
public struct LocalSnapshot: Sendable, Hashable {
    public static let historyLength = 60

    public var machine: MachineInfo
    public var latest: LocalSample
    /// The last 60 CPU totals, oldest first.
    public var cpuHistory: [Double]
    /// The last 60 receive rates, oldest first.
    public var receivedHistory: [Double]
    /// The last 60 send rates, oldest first.
    public var sentHistory: [Double]

    public init(machine: MachineInfo, latest: LocalSample, cpuHistory: [Double], receivedHistory: [Double],
                sentHistory: [Double]) {
        self.machine = machine
        self.latest = latest
        self.cpuHistory = cpuHistory
        self.receivedHistory = receivedHistory
        self.sentHistory = sentHistory
    }
}

public struct LocalReadingsConfiguration: Sendable, Hashable {
    public var kinds: Set<LocalReadingKind>
    /// Seconds between samples, 1 to 60.
    public var every: TimeInterval
    /// The volume to measure; empty for the startup volume.
    public var volumePath: String
    /// The BSD name of the interface; empty for the primary one.
    public var interface: String

    public init(kinds: Set<LocalReadingKind> = Set(LocalReadingKind.allCases), every: TimeInterval = 2,
                volumePath: String = "", interface: String = "") {
        self.kinds = kinds
        self.every = every
        self.volumePath = volumePath
        self.interface = interface
    }
}
