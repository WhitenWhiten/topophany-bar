import Foundation
import TopophanySections

/// The menu bar item's motion at the instant drawn. The app keeps the clock
/// and the turn; each renderer decides what they move. The same motion
/// draws the same frame.
public struct StatusItemMotion: Sendable {
    /// Whether anything may move. When nothing may, the item draws its
    /// still frame: no spinner, no change.
    public var moves: Bool
    /// The turn, in steps; whole steps are the rest pose.
    public var turn: Double
    /// Seconds on the app's clock.
    public var time: TimeInterval
    /// The latest change, while it settles.
    public var change: Change?

    public struct Change: Sendable {
        /// The item as it was before.
        public var from: StatusItemModel
        /// Seconds since it changed.
        public var age: TimeInterval

        public init(from: StatusItemModel, age: TimeInterval) {
            self.from = from
            self.age = age
        }
    }

    public init(moves: Bool = true, turn: Double = 0, time: TimeInterval = 0, change: Change? = nil) {
        self.moves = moves
        self.turn = turn
        self.time = time
        self.change = change
    }

    public static let still = StatusItemMotion(moves: false)
    /// How long a change takes to settle, a ripple included.
    public static let changeLength: TimeInterval = 0.9
}

/// The item's turn. It gathers speed while what the item shows is current,
/// and when that stops it slows down and comes to rest on a whole step.
public struct StatusItemTurn: Sendable {
    /// Steps per second at full speed.
    public static let speed = 1 / 2.4
    /// Seconds from rest to full speed.
    public static let spinUp = 1.2
    /// Seconds from full speed to rest at the gentlest; it can take up to a
    /// step longer to land on a whole one.
    public static let spinDown = 2.4

    public private(set) var phase = 0.0
    public private(set) var velocity = 0.0
    private var landing: Landing?

    private struct Landing: Sendable {
        var from: Double
        var speed: Double
        var braking: Double
        var to: Double
        var elapsed = 0.0
    }

    public init() {}

    public var isMoving: Bool { velocity > 0 }

    /// Moves the turn on by `seconds`, turning or coming to rest.
    public mutating func advance(by seconds: TimeInterval, turning: Bool) {
        // A stalled clock doesn't jump the turn.
        let dt = min(max(0, seconds), 0.25)
        guard dt > 0 else { return }
        if turning {
            landing = nil
            velocity = min(Self.speed, velocity + Self.speed / Self.spinUp * dt)
            phase += velocity * dt
            if phase >= 1000 { phase -= 1000 }
        } else if velocity > 0 {
            if landing == nil {
                // Brakes no harder than from full speed in `spinDown`, on
                // to the next whole step past where that would stop.
                let natural = velocity * velocity / (2 * Self.speed / Self.spinDown)
                let to = (phase + natural).rounded(.up)
                landing = Landing(from: phase, speed: velocity, braking: velocity * velocity / (2 * (to - phase)), to: to)
            }
            guard var l = landing else { return }
            l.elapsed += dt
            if l.elapsed >= l.speed / l.braking {
                phase = l.to
                velocity = 0
                landing = nil
            } else {
                phase = l.from + l.speed * l.elapsed - l.braking * l.elapsed * l.elapsed / 2
                velocity = l.speed - l.braking * l.elapsed
                landing = l
            }
        }
    }

    /// Runs on at full speed for `seconds`: the system played the turn
    /// meanwhile.
    public mutating func run(for seconds: TimeInterval) {
        guard seconds > 0 else { return }
        landing = nil
        velocity = Self.speed
        phase = (phase + Self.speed * seconds).truncatingRemainder(dividingBy: 1000)
    }

    /// Rests at once: motion is off.
    public mutating func rest() {
        phase = phase.rounded()
        velocity = 0
        landing = nil
    }
}

/// Easing for the item's motion, over 0 to 1.
enum Ease {
    static func clamp(_ t: Double) -> Double { min(1, max(0, t)) }
    /// How far `t` is from `start` to `start + length`, 0 to 1.
    static func span(_ t: Double, _ start: Double, _ length: Double) -> Double { clamp((t - start) / length) }
    static func `in`(_ t: Double) -> Double { let t = clamp(t); return t * t * t }
    static func out(_ t: Double) -> Double { let t = 1 - clamp(t); return 1 - t * t * t }
    static func inOut(_ t: Double) -> Double { let t = clamp(t); return t * t * (3 - 2 * t) }
    /// Out, past the end and back: a badge settling into place.
    static func back(_ t: Double) -> Double {
        let t = clamp(t) - 1
        let c = 1.9
        return 1 + (c + 1) * t * t * t + c * t * t
    }
    /// 0 below `low`, 1 above `high`, smooth between.
    static func step(_ low: Double, _ high: Double, _ x: Double) -> Double { inOut((x - low) / (high - low)) }
}
