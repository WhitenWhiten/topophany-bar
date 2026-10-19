import Foundation
import TopophanyKit

/// A status mark. Every mark has its own shape as well as its own color,
/// and renderers own both; this is only which one.
///
/// ● up · ▲ degraded · ✖ down · ○ unknown · ◌ offline (nothing current)
public enum Mark: String, Sendable, Hashable, CaseIterable {
    case up, degraded, down, unknown, offline

    public init(_ health: Health) {
        switch health {
        case .up: self = .up
        case .degraded: self = .degraded
        case .down: self = .down
        case .unknown: self = .unknown
        }
    }

    /// The TUI's glyph.
    public var glyph: String {
        switch self {
        case .up: "●"
        case .degraded: "▲"
        case .down: "✖"
        case .unknown: "○"
        case .offline: "◌"
        }
    }

    public var word: String {
        switch self {
        case .up: tr("up")
        case .degraded: tr("warn")
        case .down: tr("down")
        case .unknown: tr("unknown")
        case .offline: tr("not current")
        }
    }
}

extension Mark {
    /// `items` with what needs a look first: down, warn, unknown, not
    /// current, then up, each in its own order. For counting what was left
    /// out for room, so trouble left out still shows; nothing is added up.
    public static func troubleFirst<T>(_ items: [T], by mark: (T) -> Mark) -> [T] {
        func rank(_ m: Mark) -> Int {
            switch m {
            case .down: 0
            case .degraded: 1
            case .unknown: 2
            case .offline: 3
            case .up: 4
            }
        }
        return items.enumerated()
            .sorted { (rank(mark($0.element)), $0.offset) < (rank(mark($1.element)), $1.offset) }
            .map(\.element)
    }
}

/// A short state word beside an entry, such as OPEN or AFFECTED, and the
/// mark that colors it.
public struct Pill: Sendable, Hashable {
    public var text: String
    public var mark: Mark

    public init(text: String, mark: Mark) {
        self.text = text
        self.mark = mark
    }

    /// The TUI's state word, lowercased as `topo` sends it. A word this app
    /// doesn't know is shown as sent and colored by the health.
    public static func state(_ word: String, health: Health) -> Pill {
        let known: [String: String] = [
            "open": tr("OPEN"), "recovering": tr("RECOVERING"), "closed": tr("CLOSED"), "down": tr("DOWN"),
            "warn": tr("WARN"), "unknown": tr("UNKNOWN"), "affected": tr("AFFECTED"), "outdated": tr("OUTDATED"),
            "paused": tr("PAUSED"), "maintenance": tr("MAINTENANCE"), "cached": tr("CACHED"), "up": tr("UP"),
        ]
        let text = known[word] ?? (word.isEmpty ? Pill.health(health).text : word.uppercased())
        return Pill(text: text, mark: Mark(health))
    }

    /// A health's own word: UP, WARN, DOWN or UNKNOWN.
    public static func health(_ h: Health) -> Pill {
        switch h {
        case .up: Pill(text: tr("UP"), mark: .up)
        case .degraded: Pill(text: tr("WARN"), mark: .degraded)
        case .down: Pill(text: tr("DOWN"), mark: .down)
        case .unknown: Pill(text: tr("UNKNOWN"), mark: .unknown)
        }
    }

    public static var cached: Pill { Pill(text: tr("CACHED"), mark: .offline) }
}
