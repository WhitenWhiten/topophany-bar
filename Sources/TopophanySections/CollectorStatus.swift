import Foundation
import TopophanyKit

/// The existing status footer's acquisition metadata. No business verdicts.
public struct CollectorStatus: Sendable, Hashable {
    public var name: String
    public var read: CollectorRead
    public var isCurrent: Bool
    public var now: Date
    public var refreshing = false

    public init(name: String, read: CollectorRead, isCurrent: Bool, now: Date) {
        self.name = name; self.read = read; self.isCurrent = isCurrent; self.now = now
    }

    public var summary: String {
        if refreshing { return tr("Updating") }
        guard isCurrent else { return tr("Data expired") }
        if read.state == "waiting" { return tr("Waiting for data") }
        if read.state == "error" { return tr("Retrying") }
        guard read.state == "ok", let at = read.lastSuccessAt, at <= now.addingTimeInterval(ReaderPolicy.futureTolerance) else { return tr("Not known now") }
        return tr("Read \(Words.ago(at, now: now))")
    }

    public var line: String { Words.join([name, summary]) }

    public var detail: String {
        var parts = [line]
        if let at = read.lastSuccessAt, at <= now.addingTimeInterval(ReaderPolicy.futureTolerance) {
            parts.append(tr("Last successful read \(Words.ago(at, now: now))"))
        }
        if read.state == "error" {
            parts.append(Words.join([read.stage.uppercased(), read.code]))
            if let n = read.consecutiveFailures { parts.append(tr("\(n) failed reads")) }
        }
        if let ms = read.durationMS { parts.append(Words.ms(Double(ms))) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
