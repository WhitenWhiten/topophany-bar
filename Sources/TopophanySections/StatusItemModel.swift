import Foundation
import TopophanyKit

/// The menu bar item: the verdict's mark and words, and what the item is
/// doing, which is all its motion may say.
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
    public var statusColors: Bool
    /// The text beside the mark, empty for none.
    public var text: String
    /// The TUI's chip text, for the cells renderer.
    public var tuiText: String
    /// What needs attention, as Count counts it; `nil` for nothing.
    public var count: Int?
    public var activity: Activity
    /// Whether the user lets the item move.
    public var motion: Bool
    public var accessibilityLabel: String

    public init(mark: Mark, show: Settings.Appearance.Show, statusColors: Bool, text: String, tuiText: String,
                count: Int? = nil, activity: Activity = .resting, motion: Bool = false, accessibilityLabel: String) {
        self.mark = mark
        self.show = show
        self.statusColors = statusColors
        self.text = text
        self.tuiText = tuiText
        self.count = count
        self.activity = activity
        self.motion = motion
        self.accessibilityLabel = accessibilityLabel
    }

    public init(status: StatusSection, appearance: Settings.Appearance.MenuBar) {
        mark = status.mark
        show = appearance.show
        statusColors = appearance.statusColors
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
        let updated = status.updatedAt.map { tr("updated \(Words.agoSpoken($0, now: status.now))") }
        accessibilityLabel = Words.join([tr("Topophany: \(status.shortTitle)"), updated ?? ""])
            .replacingOccurrences(of: " · ", with: ", ")
    }

    /// Whether it asks for more attention than `other` did: a worse mark, or
    /// more needing attention under the same one. Only that change ripples.
    public func needsMoreAttention(than other: StatusItemModel) -> Bool {
        func rank(_ m: Mark) -> Int { m == .down ? 2 : m == .degraded ? 1 : 0 }
        if rank(mark) != rank(other.mark) { return rank(mark) > rank(other.mark) }
        return rank(mark) > 0 && (count ?? 0) > (other.count ?? 0)
    }
}
