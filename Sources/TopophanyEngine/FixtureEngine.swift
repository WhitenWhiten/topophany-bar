import Foundation
import Synchronization
import TopophanyKit

/// Replays NDJSON fixtures written to PROTOCOL.md, with time under control.
///
/// Fixture times are anchored at `anchor`: replay shifts them so the anchor
/// is the moment `start` was called. Frames at or before it are sent at once,
/// later ones when the clock reaches them. A looping fixture repeats the
/// frames after the anchor. Each frame is fitted to the running request, as
/// `topo` would answer it: its rows in the request's order and IDs, the
/// attention list cut to the request's limit, an unknown node missing.
public final class FixtureEngine: Engine {
    public enum Scenario: String, CaseIterable, Sendable {
        case clear, degraded, incidents, incomplete, offline, stale, stopped
        case errorFrame = "error-frame"
        case unknownNode = "unknown-node"

        /// Whether the fixture repeats after its last frame. A stale fixture
        /// stops writing, so its lease lapses.
        public var loops: Bool { self != .stale && self != .stopped }
    }

    /// The profiles a fixture launch offers, as `--profiles` would list them.
    public static let profiles = ProfileList(profiles: [
        .init(name: "home", project: "homelab", active: true),
        .init(name: "work", project: "acme"),
    ])

    public static let anchor = Timestamp.parse("2026-10-18T13:30:00Z")!

    private struct Item: Sendable {
        var at: Date
        var object: [String: JSONValue]
    }

    private struct State: Sendable {
        var request: Request?
        var continuation: AsyncStream<EngineEvent>.Continuation?
        var origin = Date()
        var next = 0
        var cycle = 0
        var sequence: UInt64 = 0
        var last: [String: JSONValue]?
        var lastAt = Date()
        var ended = false
        var pump: Task<Void, Never>?
    }

    public let name: String
    private let items: [Item]
    private let loops: Bool
    private let clock: any WallClock
    private let tick: Duration?
    private let state = Mutex(State())

    /// - Parameter tick: how often to check the clock; `nil` to step only
    ///   through `pump()`.
    public convenience init(scenario: Scenario, clock: any WallClock = SystemClock(), tick: Duration? = .milliseconds(250)) {
        let url = Bundle.module.url(forResource: scenario.rawValue, withExtension: "ndjson", subdirectory: "Fixtures")!
        let data = (try? Data(contentsOf: url)) ?? Data()
        self.init(name: scenario.rawValue, ndjson: data, loops: scenario.loops, clock: clock, tick: tick)
    }

    public init(name: String, ndjson: Data, loops: Bool, clock: any WallClock = SystemClock(), tick: Duration? = .milliseconds(250)) {
        self.name = name
        self.loops = loops
        self.clock = clock
        self.tick = tick
        var items: [Item] = []
        for line in ndjson.split(separator: 0x0A) where !line.isEmpty {
            guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: line),
                  case .string(let g)? = o["generated_at"], let at = Timestamp.parse(g) else { continue }
            items.append(Item(at: at, object: o))
        }
        self.items = items.sorted { $0.at < $1.at }
    }

    /// The fixture's frames, unfitted, as stored.
    public static func lines(_ scenario: Scenario) -> [Data] {
        guard let url = Bundle.module.url(forResource: scenario.rawValue, withExtension: "ndjson", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).map { Data($0) }
    }

    public func start(_ request: Request) -> AsyncStream<EngineEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        let now = clock.now()
        state.withLock {
            $0.request = request
            $0.continuation = continuation
            $0.origin = now
        }
        continuation.yield(.status(.running(.init(pid: 0, path: "fixture:" + name, version: "fixture", startedAt: now))))
        pump()
        if let tick {
            let task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: tick)
                    guard let self else { return }
                    if self.pump() { return }
                }
            }
            state.withLock { $0.pump = task }
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { $0.pump?.cancel() }
        }
        return stream
    }

    public func update(_ request: Request) async throws {
        let (c, frame) = state.withLock { s -> (AsyncStream<EngineEvent>.Continuation?, EngineEvent?) in
            s.request = request
            guard !s.ended, let last = s.last else { return (s.continuation, nil) }
            return (s.continuation, self.fit(last, at: s.lastAt, state: &s))
        }
        if let frame { c?.yield(frame) }
    }

    public func stop() async {
        let c = state.withLock { s -> AsyncStream<EngineEvent>.Continuation? in
            s.pump?.cancel()
            let c = s.continuation
            if !s.ended, let c {
                s.ended = true
                s.sequence += 1
                let now = self.clock.now()
                let o: [String: JSONValue] = [
                    "schema": .number(1), "name": .string("stream"), "request_id": .string(s.request?.requestID ?? ""),
                    "instance": .string("fixture-" + self.name), "sequence": .number(Double(s.sequence)),
                    "lifecycle": .string("stopped"), "generated_at": .string(Timestamp.format(now)),
                    "publisher_expires_at": .string(Timestamp.format(now)), "rows": .array([]),
                ]
                if let e = Self.event(o) { c.yield(e) }
                c.yield(.status(.stopped))
            }
            s.continuation = nil
            return c
        }
        c?.finish()
    }

    /// Sends every frame that is due by the clock. Returns true once the
    /// fixture has nothing more to send.
    @discardableResult
    public func pump() -> Bool {
        let now = clock.now()
        var events: [EngineEvent] = []
        let (c, done) = state.withLock { s -> (AsyncStream<EngineEvent>.Continuation?, Bool) in
            guard !s.ended, let c = s.continuation, !items.isEmpty else { return (nil, true) }
            let shift = s.origin.timeIntervalSince(Self.anchor)
            // A loop repeats the frames after the anchor, keeping their spacing.
            let tail = items.firstIndex { $0.at > Self.anchor } ?? items.count
            let spacing = items.count > 1 ? items[items.count - 1].at.timeIntervalSince(items[items.count - 2].at) : 10
            let period = tail < items.count ? items.last!.at.timeIntervalSince(items[tail].at) + max(1, spacing) : 0
            while true {
                if s.next >= items.count {
                    guard loops, tail < items.count else { break }
                    s.cycle += 1
                    s.next = tail
                }
                let item = items[s.next]
                let at = item.at.addingTimeInterval(shift + Double(s.cycle) * period)
                guard at <= now else { break }
                s.next += 1
                if case .string("stopped")? = item.object["lifecycle"] {
                    s.ended = true
                    if let e = fit(item.object, at: at, state: &s) { events.append(e) }
                    events.append(.status(.stopped))
                    break
                }
                if case .string("error")? = item.object["lifecycle"] {
                    if let e = Self.event(Self.shifted(item.object, by: at.timeIntervalSince(item.at))) { events.append(e) }
                    continue
                }
                s.last = item.object
                s.lastAt = at
                if let e = fit(item.object, at: at, state: &s) { events.append(e) }
            }
            let done = s.ended || (!loops && s.next >= items.count)
            return (c, done)
        }
        for e in events { c?.yield(e) }
        return done
    }

    // MARK: fitting a frame to the request

    private func fit(_ object: [String: JSONValue], at: Date, state s: inout State) -> EngineEvent? {
        s.sequence += 1
        return Self.event(Self.fitted(object, at: at, sequence: s.sequence, request: s.request))
    }

    /// A fixture frame moved to `at` and fitted to `request`.
    static func fitted(_ object: [String: JSONValue], at: Date, sequence: UInt64, request: Request?) -> [String: JSONValue] {
        let original = (object["generated_at"].flatMap { if case .string(let g) = $0 { Timestamp.parse(g) } else { nil } }) ?? at
        var o = shifted(object, by: at.timeIntervalSince(original))
        o["sequence"] = .number(Double(sequence))
        if let r = request {
            o["request_id"] = .string(r.requestID)
            o["observer"] = .string(r.observer)
            o["bar_row"] = .string(r.template.bar.row)
            o["title"] = .string(r.template.title)
            if case .array(let rows)? = o["rows"], !rows.isEmpty {
                o["rows"] = .array(Self.rows(rows, for: r.template))
            }
        }
        return o
    }

    /// The fixture's frames, fitted to `request` and moved so that the anchor
    /// is `origin`; one pass, without looping. Error and stopped frames
    /// are included as they are.
    public static func timeline(_ scenario: Scenario, request: Request, origin: Date) -> [(at: Date, frame: Frame, line: Data)] {
        let shift = origin.timeIntervalSince(anchor)
        var out: [(Date, Frame, Data)] = []
        var sequence: UInt64 = 0
        for line in lines(scenario) {
            guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: line),
                  case .string(let g)? = o["generated_at"], let t = Timestamp.parse(g) else { continue }
            let at = t.addingTimeInterval(shift)
            let fitted: [String: JSONValue]
            if case .string("error")? = o["lifecycle"] {
                fitted = shifted(o, by: shift)
            } else {
                sequence += 1
                fitted = Self.fitted(o, at: at, sequence: sequence, request: request)
            }
            if case .frame(let f, let l)? = event(fitted) { out.append((at, f, l)) }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    static func rows(_ fixture: [JSONValue], for template: Template) -> [JSONValue] {
        func string(_ v: JSONValue?) -> String? { if case .string(let s)? = v { s } else { nil } }
        func node(_ row: [String: JSONValue]) -> String? {
            if case .object(let sel)? = row["select"] { return string(sel["node"]) }
            return nil
        }
        let objects = fixture.compactMap { if case .object(let o) = $0 { o } else { nil } }
        return template.rows.map { t in
            let match = objects.first { o in
                string(o["metric"]) == t.metric && (t.metric != "server.card" || node(o) == t.select?.node)
            }
            var row = match ?? [
                "value": .null, "text": .string("unknown"), "health": .string("unknown"),
                "freshness": .string("unavailable"),
                "reason": .string(t.metric == "server.card" ? "entity_missing" : "source_unavailable"),
            ]
            row["id"] = .string(t.id)
            row["metric"] = .string(t.metric)
            row["visual"] = .string(t.visual)
            var sel: [String: JSONValue] = [:]
            if let n = t.select?.node { sel["node"] = .string(n) }
            row["select"] = .object(sel)
            if t.metric == "attention.list" {
                let limit = t.limit ?? 5
                row["limit"] = .number(Double(limit))
                if case .object(var v)? = row["value"], case .array(let items)? = v["items"] {
                    v["items"] = .array(Array(items.prefix(limit)))
                    row["value"] = .object(v)
                }
            } else {
                row.removeValue(forKey: "limit")
            }
            return .object(row)
        }
    }

    static func shifted(_ object: [String: JSONValue], by seconds: TimeInterval) -> [String: JSONValue] {
        guard case .object(let o) = shift(.object(object), by: seconds) else { return object }
        return o
    }

    static func shift(_ v: JSONValue, by seconds: TimeInterval) -> JSONValue {
        switch v {
        case .string(let s):
            guard s.count >= 20, let d = Timestamp.parse(s) else { return v }
            return .string(Timestamp.format(d.addingTimeInterval(seconds)))
        case .array(let a): return .array(a.map { shift($0, by: seconds) })
        case .object(let o): return .object(o.mapValues { shift($0, by: seconds) })
        default: return v
        }
    }

    static func event(_ object: [String: JSONValue]) -> EngineEvent? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let line = try? e.encode(JSONValue.object(object)), let frame = FrameDecoder.frame(from: line) else { return nil }
        return .frame(frame, line: line)
    }
}

extension FixtureEngine {
    /// What a reader shows `after` seconds past the anchor of a scenario
    /// replayed from `origin`: every frame due by then received when it was
    /// due, then the reader rules applied at that moment.
    public static func reading(_ scenario: Scenario, request: Request, origin: Date, after: TimeInterval) -> Reading {
        policy(scenario, request: request, origin: origin, after: after).evaluate(at: origin.addingTimeInterval(after))
    }

    /// A reader that has received the fixture's frames up to `after`.
    public static func policy(_ scenario: Scenario, request: Request, origin: Date, after: TimeInterval) -> ReaderPolicy {
        let now = origin.addingTimeInterval(after)
        var policy = ReaderPolicy()
        policy.sourceStarted()
        for (at, frame, line) in timeline(scenario, request: request, origin: origin) where at <= now {
            policy.receive(frame, line: line, at: at)
            if frame.lifecycle == .stopped { policy.sourceEnded(at: at) }
        }
        return policy
    }
}
