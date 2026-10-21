import Foundation
import LocalReadings
import TopophanyKit

/// The menu bar item: the verdict's mark and words, what the item is doing,
/// which is all its motion may say, and this Mac's readings beside it.
public struct StatusItemModel: Sendable, Hashable {
    public enum Activity: Sendable, Hashable {
        /// What it shows is current.
        case live
        /// `topo` is starting, or starts again shortly.
        case connecting
        /// Nothing current is known.
        case resting
    }

    public var mark: Mark
    public var show: Settings.Appearance.Show
    public var icon: Settings.Appearance.MenuBar.Icon = .globe
    public var customIconID: String?
    public var iconSize = 26
    public var iconSpeed = 1.0
    public var statusColors: Bool
    /// The user quieted its alert until it gets worse: the badge keeps its
    /// shape, in the menu bar's ink.
    public var quiet: Bool
    /// The text beside the mark, empty for none.
    public var text: String
    /// The TUI's chip text, for the cells renderer.
    public var tuiText: String
    /// What needs attention, as Count counts it; `nil` for nothing.
    public var count: Int?
    public var activity: Activity
    /// Whether the user lets the item move.
    public var motion: Bool
    /// This Mac's readings beside the item: local readings, not evidence.
    public var readings: [MenuBarReading]
    public var accessibilityLabel: String

    public init(mark: Mark, show: Settings.Appearance.Show, statusColors: Bool, quiet: Bool = false, text: String,
                tuiText: String, count: Int? = nil, activity: Activity = .resting, motion: Bool = false,
                readings: [MenuBarReading] = [], accessibilityLabel: String) {
        self.mark = mark
        self.show = show
        self.statusColors = statusColors
        self.quiet = quiet
        self.text = text
        self.tuiText = tuiText
        self.count = count
        self.activity = activity
        self.motion = motion
        self.readings = readings
        self.accessibilityLabel = accessibilityLabel
    }

    public init(status: StatusSection, appearance: Settings.Appearance.MenuBar, local: LocalSnapshot? = nil,
                quiet: QuietAlert? = nil) {
        mark = status.mark
        show = appearance.show
        icon = appearance.icon
        customIconID = appearance.customIconID
        iconSize = appearance.iconSize
        iconSpeed = appearance.iconSpeed
        statusColors = appearance.statusColors
        self.quiet = appearance.statusColors && quiet != nil && QuietAlert.alerts(status)
        switch appearance.show {
        case .symbol:
            text = ""
            tuiText = ""
        case .count:
            text = status.count.map(String.init) ?? ""
            tuiText = text
        case .words:
            text = status.shortTitle
            tuiText = status.tuiShortTitle
        }
        count = status.count
        switch status.kind {
        case .verdict(.cached): activity = .resting
        case .verdict: activity = .live
        case .blind(.starting): activity = .connecting
        case .blind(.engineStopped(let at)): activity = at == nil ? .resting : .connecting
        case .blind: activity = .resting
        }
        motion = appearance.motion
        readings = appearance.readings.map { MenuBarReading($0, local) }
        let updated = status.updatedAt.map { tr("updated \(Words.agoSpoken($0, now: status.now))") }
        let verdict = Words.join([tr("Topophany: \(status.shortTitle)"), self.quiet ? tr("quieted") : "", updated ?? ""])
            .replacingOccurrences(of: " · ", with: ", ")
        let mac = readings.map(\.spoken).joined(separator: ", ")
        accessibilityLabel = readings.isEmpty ? verdict : verdict + "\n" + tr("This Mac: \(mac)")
    }

    /// Draws its marks in their status colors: on, and not quieted.
    public var tinted: Bool { statusColors && !quiet }

    /// Whether it asks for more attention than `other` did: a worse mark, or
    /// more needing attention under the same one. Only that change ripples.
    public func needsMoreAttention(than other: StatusItemModel) -> Bool {
        Self.asksMoreAttention(mark, count, than: other.mark, other.count)
    }

    /// ✖ over ▲ over the rest, then more under the same mark.
    public static func asksMoreAttention(_ mark: Mark, _ count: Int?, than other: Mark, _ otherCount: Int?) -> Bool {
        func rank(_ m: Mark) -> Int { m == .down ? 2 : m == .degraded ? 1 : 0 }
        if rank(mark) != rank(other) { return rank(mark) > rank(other) }
        return rank(mark) > 0 && (count ?? 0) > (otherCount ?? 0)
    }
}

/// One of this Mac's readings beside the menu bar item. They carry no
/// health, so the item draws them in the menu bar's own ink.
public struct MenuBarReading: Sendable, Hashable, Identifiable {
    public typealias Kind = Settings.Appearance.MenuBar.Reading

    public var kind: Kind
    /// CPU or memory in use, 0 to 1; `nil` before the first sample.
    public var fraction: Double?
    /// CPU: the latest samples, 0 to 1, oldest first.
    public var history: [Double]
    /// Network: bytes per second; `nil` before the first sample.
    public var received: Double?
    public var sent: Double?

    public var id: Kind { kind }

    public init(kind: Kind, fraction: Double? = nil, history: [Double] = [], received: Double? = nil, sent: Double? = nil) {
        self.kind = kind
        self.fraction = fraction
        self.history = history
        self.received = received
        self.sent = sent
    }

    /// The reading in the latest snapshot.
    public init(_ kind: Kind, _ local: LocalSnapshot?) {
        func unit(_ percent: Double) -> Double { min(1, max(0, percent / 100)) }
        switch kind {
        case .cpu:
            self.init(kind: kind, fraction: local?.latest.cpu.map { unit($0.total) }, history: (local?.cpuHistory ?? []).map(unit))
        case .memory:
            self.init(kind: kind, fraction: local?.latest.memory.map { unit($0.usedPercent) })
        case .network:
            self.init(kind: kind, received: local?.latest.network?.receivedPerSecond, sent: local?.latest.network?.sentPerSecond)
        }
    }

    /// "17%"; "–" before the first sample.
    public var value: String { fraction.map { Words.percent($0 * 100, digits: 0) } ?? "–" }
    /// "1.4 MB/s"; "–" before the first sample.
    public var receivedText: String { received.map(Words.shortRate) ?? "–" }
    public var sentText: String { sent.map(Words.shortRate) ?? "–" }

    /// The widest each value can be, so the item holds still as they change.
    public static let widestPercent = "100%"
    public static let widestRate = "88.8 MB/s"

    /// "CPU 17%", for VoiceOver and the tooltip.
    public var spoken: String {
        switch kind {
        case .cpu: tr("CPU \(fraction == nil ? tr("no reading") : value)")
        case .memory: tr("memory \(fraction == nil ? tr("no reading") : value)")
        case .network:
            received == nil && sent == nil ? tr("network \(tr("no reading"))") : tr("network \(receivedText) in, \(sentText) out")
        }
    }
}
