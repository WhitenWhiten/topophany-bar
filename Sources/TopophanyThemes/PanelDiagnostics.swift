#if DEBUG
import Foundation
import Synchronization

/// Opt-in counters for the running panel. Release builds carry no probes.
/// The debug driver records these alongside actual scroll offsets, so a
/// cheap state update cannot conceal an expensive view or Canvas redraw.
public enum PanelDiagnostics {
    private struct Counter: Codable {
        var count = 0
        var milliseconds = 0.0
        var maximumMilliseconds = 0.0
    }

    private static let counters = Mutex<[String: Counter]?>(nil)

    public static var isRecording: Bool { counters.withLock { $0 != nil } }

    public static func start() { counters.withLock { $0 = [:] } }

    public static func stop() -> String {
        let result = counters.withLock { value in
            let result = value ?? [:]
            value = nil
            return result
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(decoding: encoder.encode(result), as: UTF8.self)) ?? "{}"
    }

    public static func count(_ name: String) {
        counters.withLock { value in
            guard value != nil else { return }
            value![name, default: Counter()].count += 1
        }
    }

    public static func interval(_ name: String) -> Interval? {
        counters.withLock { $0 == nil ? nil : Interval(name: name) }
    }

    public struct Interval {
        fileprivate var name: String
        private let start = ProcessInfo.processInfo.systemUptime

        public func end() {
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            counters.withLock { value in
                guard value != nil else { return }
                value![name, default: Counter()].count += 1
                value![name]!.milliseconds += elapsed
                value![name]!.maximumMilliseconds = max(value![name]!.maximumMilliseconds, elapsed)
            }
        }
    }
}
#endif
