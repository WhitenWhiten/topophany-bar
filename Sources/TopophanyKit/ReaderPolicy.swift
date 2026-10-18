import Foundation

/// The reader rules of PROTOCOL.md §5, as `topo monitor preview` applies
/// them. The policy keeps the last `running` frame and, every time it is
/// asked, says what of it may still be shown at that moment.
///
/// - Past `publisher_expires_at`, nothing is current.
/// - Past a row's `valid_until`, that row is withheld. A row with a value and
///   no `valid_until` is withheld too, as `topo` withholds it.
/// - A timestamp more than five minutes beyond the clock is implausible.
/// - A row is never extended by a later lease: its own deadline is the only
///   one that counts.
/// - The source ending (process exit, stdout closed) is unavailable at once.
/// - An error frame is never content; the last running frame stays.
public struct ReaderPolicy: Sendable {
    /// How far beyond the clock a timestamp may lie and still be believed.
    public static let futureTolerance: TimeInterval = 5 * 60

    public enum Source: Sendable, Hashable {
        /// Nothing has started yet.
        case waiting
        /// The engine is running and its stdout is open.
        case open
        /// The process exited or its stdout closed.
        case ended(at: Date)
        /// `topo` wrote its final `stopped` frame.
        case stopped(at: Date)
    }

    public private(set) var source: Source = .waiting
    /// The last `running` frame, and the line it came from.
    public private(set) var frame: Frame?
    public private(set) var line: Data?
    public private(set) var receivedAt: Date?
    /// The last error frame since the last running frame.
    public private(set) var error: Frame.Problem?
    public private(set) var errorRequestID: String?
    /// The last verdict that was current when it arrived, kept as history.
    public private(set) var lastKnown: LastKnown?

    public init() {}

    /// Restores what the policy knew, as the widget hand-off keeps it.
    public init(frame: Frame?, line: Data?, receivedAt: Date?, lastKnown: LastKnown?, source: Source) {
        self.frame = frame
        self.line = line
        self.receivedAt = receivedAt
        self.lastKnown = lastKnown
        self.source = source
    }

    /// A new process started. What an ended source left stays unavailable
    /// until the new one's first frame: ◌ until then.
    public mutating func sourceStarted() {
        if case .waiting = source { source = .open }
    }

    public mutating func sourceEnded(at now: Date) {
        if case .stopped = source { return }
        source = .ended(at: now)
    }

    public mutating func receive(_ incoming: Frame, line: Data? = nil, at now: Date) {
        switch incoming.lifecycle {
        case .running:
            if let f = frame, f.instance == incoming.instance, !f.instance.isEmpty,
               let a = f.sequence, let b = incoming.sequence, b <= a {
                return
            }
            frame = incoming
            self.line = line
            receivedAt = now
            error = nil
            errorRequestID = nil
            source = .open
            // History: the last verdict that was current when topo stated it.
            if let g = incoming.generatedAt, g <= now.addingTimeInterval(Self.futureTolerance),
               let v = Self.currentVerdict(in: incoming, at: g) {
                lastKnown = LastKnown(verdict: v, at: g)
            }
        case .error:
            error = incoming.error ?? Frame.Problem(code: "error", message: "")
            errorRequestID = incoming.requestID
        case .stopped:
            source = .stopped(at: now)
        case .other:
            break
        }
    }

    public func evaluate(at now: Date) -> Reading {
        let availability = availability(at: now)
        var rows: [RowReading] = []
        if let frame {
            for row in frame.rows {
                rows.append(Self.read(row, availability: availability, at: now))
            }
        }
        return Reading(now: now, availability: availability, frame: frame, receivedAt: receivedAt, rows: rows,
                       error: error, errorRequestID: errorRequestID, lastKnown: lastKnown)
    }

    func availability(at now: Date) -> Reading.Availability {
        switch source {
        case .ended(let at): return .sourceEnded(since: at)
        case .stopped(let at): return .stopped(since: at)
        case .waiting, .open: break
        }
        guard let frame else { return .waiting }
        guard frame.schema == 1 else { return .unsupported }
        guard let generated = frame.generatedAt, let expires = frame.publisherExpiresAt else { return .implausible }
        let horizon = now.addingTimeInterval(Self.futureTolerance)
        if generated > horizon || expires > horizon { return .implausible }
        if now >= expires { return .leaseExpired(since: expires) }
        return .live
    }

    static func read(_ row: Row, availability: Reading.Availability, at now: Date) -> RowReading {
        guard availability == .live else { return RowReading(row: row, status: .withheld(.unavailable)) }
        guard row.value.isKnown else { return RowReading(row: row, status: .withheld(.noValue)) }
        guard let until = row.validUntil, now < until else { return RowReading(row: row, status: .withheld(.expired)) }
        let horizon = now.addingTimeInterval(futureTolerance)
        if until > horizon || (row.sampledAt.map { $0 > horizon } ?? false) {
            return RowReading(row: row, status: .withheld(.implausible))
        }
        return RowReading(row: row, status: .current)
    }

    static func currentVerdict(in frame: Frame, at now: Date) -> Verdict? {
        var p = ReaderPolicy()
        p.frame = frame
        p.source = .open
        let reading = p.evaluate(at: now)
        guard let r = reading.row(frame.barRow.isEmpty ? "status" : frame.barRow) ?? reading.rows.first(where: {
            $0.row.metric == "summary.verdict"
        }), case .verdict(let v) = r.value else { return nil }
        return v
    }
}

/// The last verdict that was current, kept as history: "last known".
public struct LastKnown: Sendable, Hashable, Codable {
    public var state: String
    public var text: String
    public var glyph: String
    public var incidents: Int?
    public var at: Date

    public init(verdict: Verdict, at: Date) {
        state = verdict.state.rawValue
        text = verdict.text
        glyph = verdict.glyph
        incidents = verdict.incidents
        self.at = at
    }

    public var verdictState: VerdictState { VerdictState(state) }
}

/// What may be shown at one moment.
public struct Reading: Sendable {
    public enum Availability: Sendable, Hashable {
        /// No frame has arrived yet.
        case waiting
        case live
        case leaseExpired(since: Date)
        /// A frame's times lie implausibly far in the future, or are missing.
        case implausible
        case sourceEnded(since: Date)
        case stopped(since: Date)
        case unsupported
    }

    public var now: Date
    public var availability: Availability
    /// The last running frame, current or not. Use it for metadata only;
    /// values come from `rows`.
    public var frame: Frame?
    public var receivedAt: Date?
    public var rows: [RowReading]
    public var error: Frame.Problem?
    public var errorRequestID: String?
    public var lastKnown: LastKnown?

    public init(now: Date, availability: Availability, frame: Frame?, receivedAt: Date?, rows: [RowReading],
                error: Frame.Problem?, errorRequestID: String?, lastKnown: LastKnown?) {
        self.now = now
        self.availability = availability
        self.frame = frame
        self.receivedAt = receivedAt
        self.rows = rows
        self.error = error
        self.errorRequestID = errorRequestID
        self.lastKnown = lastKnown
    }

    public var isLive: Bool { availability == .live }

    public func row(_ id: String) -> RowReading? { rows.first { $0.row.id == id } }
}

public struct RowReading: Sendable, Hashable {
    public enum Withheld: Sendable, Hashable {
        /// The frame isn't current: lease lapsed, source ended or stopped.
        case unavailable
        /// `topo` sent no value: it doesn't know.
        case noValue
        /// The row's `valid_until` has passed.
        case expired
        /// The row's times lie implausibly far in the future.
        case implausible
    }

    public enum Status: Sendable, Hashable {
        case current
        case withheld(Withheld)
    }

    public var row: Row
    public var status: Status

    public init(row: Row, status: Status) {
        self.row = row
        self.status = status
    }

    public var isCurrent: Bool { status == .current }

    /// The value, only while it is current.
    public var value: RowValue { isCurrent ? row.value : .none }
}
