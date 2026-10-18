import Foundation
import Network
import Synchronization
#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

/// Samples this Mac on a fixed cadence and keeps a minute of history for
/// the sparklines. Everything is read in-process; nothing runs a command.
public final class LocalReadingsMonitor: Sendable {
    public let configuration: LocalReadingsConfiguration

    private let path = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "LocalReadings.path")
    /// The current path's interfaces, preferred first.
    private let available = Mutex<[NWInterface]?>(nil)
    private let started = Mutex(false)

    public init(configuration: LocalReadingsConfiguration) {
        self.configuration = configuration
    }

    deinit { path.cancel() }

    /// Samples at once, then every `configuration.every` seconds, until the
    /// consumer stops listening. A monitor starts once; a second call gets
    /// an empty stream.
    public func snapshots() -> AsyncStream<LocalSnapshot> {
        let first = started.withLock { s in
            defer { s = true }
            return !s
        }
        guard first else { return AsyncStream { $0.finish() } }
        let config = configuration
        if config.kinds.contains(.network) {
            path.pathUpdateHandler = { [weak self] p in self?.available.withLock { $0 = p.availableInterfaces } }
            path.start(queue: pathQueue)
        }
        let (stream, continuation) = AsyncStream.makeStream(of: LocalSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        let task = Task { [self] in await run(config, continuation) }
        continuation.onTermination = { [path] _ in
            task.cancel()
            path.cancel()
        }
        return stream
    }

    /// Mounted local volumes, for the Settings picker.
    public static func volumes() -> [(name: String, path: String)] { StorageSampler.volumes() }

    /// Interfaces that are up, have an address and that the system names
    /// (so not tunnels or peer-to-peer links), for the Settings picker.
    public static func interfaces() -> [(name: String, displayName: String)] {
        let names = InterfaceNames.localized()
        let active = NetworkSampler.activeInterfaces()
        let named = active.filter { names[$0] != nil }
        return (named.isEmpty ? active : named).map { ($0, names[$0] ?? $0) }
    }

    private func run(_ c: LocalReadingsConfiguration, _ out: AsyncStream<LocalSnapshot>.Continuation) async {
        let machine = MachineInfo.current()
        let every = min(60, max(1, c.every))
        var cpu = CPUSampler()
        var memory = MemorySampler()
        var storage = StorageSampler(path: c.volumePath)
        var battery = BatterySampler()
        var network: NetworkSampler?
        var cpuHistory: [Double] = []
        var rxHistory: [Double] = []
        var txHistory: [Double] = []
        func keep(_ v: Double, in h: inout [Double]) {
            h.append(v)
            if h.count > LocalSnapshot.historyLength { h.removeFirst(h.count - LocalSnapshot.historyLength) }
        }

        // Rates need two readings: prime them, so the first snapshot has
        // every value.
        if c.kinds.contains(.cpu) { _ = cpu.sample(at: Date()) }
        if c.kinds.contains(.network) {
            // Give the path monitor a moment to report the primary interface.
            try? await Task.sleep(for: .milliseconds(150))
            network = sampler(for: c)
            _ = network?.sample(at: Date())
        }
        try? await Task.sleep(for: .milliseconds(350))

        while !Task.isCancelled {
            let now = Date()
            var s = LocalSample(at: now)
            if c.kinds.contains(.cpu) {
                s.cpu = cpu.sample(at: now)
                if let v = s.cpu?.total { keep(v, in: &cpuHistory) }
            }
            if c.kinds.contains(.memory) { s.memory = memory.sample(at: now) }
            if c.kinds.contains(.storage) { s.storage = storage.sample(at: now) }
            if c.kinds.contains(.battery) { s.battery = battery.sample(at: now) }
            if c.kinds.contains(.network) {
                let wanted = interface(for: c)
                if network?.interface != wanted.name {
                    network = wanted.name.isEmpty ? nil : NetworkSampler(interface: wanted.name, displayName: wanted.display)
                    rxHistory.removeAll()
                    txHistory.removeAll()
                }
                network?.displayName = wanted.display
                s.network = network?.sample(at: now)
                if let n = s.network {
                    keep(n.receivedPerSecond, in: &rxHistory)
                    keep(n.sentPerSecond, in: &txHistory)
                }
            }
            out.yield(LocalSnapshot(machine: machine, latest: s, cpuHistory: cpuHistory, receivedHistory: rxHistory,
                                    sentHistory: txHistory))
            do {
                try await Task.sleep(for: .seconds(every))
            } catch {
                break
            }
        }
        out.finish()
    }

    private func sampler(for c: LocalReadingsConfiguration) -> NetworkSampler? {
        let w = interface(for: c)
        return w.name.isEmpty ? nil : NetworkSampler(interface: w.name, displayName: w.display)
    }

    /// The interface to measure: the configured one, else the path's
    /// preferred one, else the first active `en` interface.
    private func interface(for c: LocalReadingsConfiguration) -> (name: String, display: String) {
        let path = available.withLock { $0 } ?? []
        let name: String
        if !c.interface.isEmpty {
            name = c.interface
        } else if let p = path.first(where: { $0.type != .loopback && $0.type != .other }) ?? path.first {
            name = p.name
        } else {
            let active = NetworkSampler.activeInterfaces()
            name = active.first { $0.hasPrefix("en") } ?? active.first ?? ""
        }
        guard !name.isEmpty else { return ("", "") }
        switch path.first(where: { $0.name == name })?.type {
        case .wifi: return (name, "Wi-Fi")
        case .wiredEthernet: return (name, "Ethernet")
        default: return (name, InterfaceNames.localized()[name] ?? name)
        }
    }
}

enum InterfaceNames {
    /// The system's display names by BSD name, such as "Wi-Fi" for en0.
    static func localized() -> [String: String] {
        var out: [String: String] = [:]
        #if canImport(SystemConfiguration)
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for i in all {
                if let bsd = SCNetworkInterfaceGetBSDName(i) as String?,
                   let name = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? {
                    out[bsd] = name
                }
            }
        }
        #endif
        return out
    }
}
