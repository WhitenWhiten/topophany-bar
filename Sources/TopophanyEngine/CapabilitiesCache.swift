import Foundation
import TopophanyKit

/// Coalesces probes from the supervisor and Settings. The condition protects
/// both dictionaries; the subprocess runs with the lock released.
final class CapabilitiesCache: @unchecked Sendable {
    static let shared = CapabilitiesCache(probe: ProcessEngine.probe)

    private struct Stamp: Equatable {
        var modified: Date?
        var size: UInt64?
        var inode: UInt64?
    }
    private struct Entry {
        var stamp: Stamp
        var result: Result<Capabilities, EngineProblem>
        var expires: Date
        var timeout: TimeInterval
    }
    private let condition = NSCondition()
    private var entries: [String: Entry] = [:]
    private var checking = Set<String>()
    private let probe: @Sendable (String, TimeInterval) -> Result<Capabilities, EngineProblem>
    private let clock: any WallClock

    init(clock: any WallClock = SystemClock(), probe: @escaping @Sendable (String, TimeInterval) -> Result<Capabilities, EngineProblem>) {
        self.clock = clock
        self.probe = probe
    }

    func check(_ path: String, timeout: TimeInterval) -> Result<Capabilities, EngineProblem> {
        let real = URL(filePath: path).resolvingSymlinksInPath().path
        let a = (try? FileManager.default.attributesOfItem(atPath: real)) ?? [:]
        let stamp = Stamp(modified: a[.modificationDate] as? Date, size: (a[.size] as? NSNumber)?.uint64Value,
                          inode: (a[.systemFileNumber] as? NSNumber)?.uint64Value)
        condition.lock()
        while checking.contains(real) { condition.wait() }
        if let entry = entries[real], entry.stamp == stamp, clock.now() < entry.expires {
            let usable: Bool
            switch entry.result {
            case .success: usable = true
            case .failure: usable = entry.timeout >= timeout
            }
            if usable { condition.unlock(); return entry.result }
        }
        checking.insert(real)
        condition.unlock()
        let result = probe(path, timeout)
        let lifetime: TimeInterval = if case .success = result { 60 } else { 2 }
        condition.lock()
        if entries.count >= 64 { entries.removeAll(keepingCapacity: true) }
        entries[real] = Entry(stamp: stamp, result: result, expires: clock.now().addingTimeInterval(lifetime), timeout: timeout)
        checking.remove(real)
        condition.broadcast()
        condition.unlock()
        return result
    }
}
