import Foundation
import Testing
@testable import TopophanyEngine
@testable import TopophanyKit

func request(_ id: String = "settings-1", limit: Int = 3, nodes: [String] = ["oracle-ny", "bwh-la"], mac: String? = "macbook") -> Request {
    var s = Settings()
    s.sections.attentionLimit = limit
    s.sections.servers = true
    s.sections.serverNodes = nodes
    if let mac {
        s.sections.mac.mode = .server
        s.sections.mac.node = mac
    }
    var r = TemplateCompiler().request(for: s, revision: 1)
    r.requestID = id
    return r
}

/// Reads exactly `n` events that are already buffered.
func take(_ n: Int, from it: inout AsyncStream<EngineEvent>.Iterator) async -> [EngineEvent] {
    var out: [EngineEvent] = []
    for _ in 0..<n {
        guard let e = await it.next() else { break }
        out.append(e)
    }
    return out
}

func frames(_ events: [EngineEvent]) -> [Frame] {
    events.compactMap { if case .frame(let f, _) = $0 { f } else { nil } }
}

@Suite struct FixtureEngineTests {
    let t = Timestamp.parse("2027-01-01T00:00:00Z")!

    @Test func everyFixtureFollowsTheProtocol() throws {
        for scenario in FixtureEngine.Scenario.allCases {
            let lines = FixtureEngine.lines(scenario)
            #expect(!lines.isEmpty, "\(scenario)")
            for line in lines {
                #expect(line.count <= FrameDecoder.maxLineBytes)
                let f = try #require(FrameDecoder.frame(from: line), "\(scenario)")
                #expect(f.schema == 1)
                #expect(f.name == "stream")
                if f.lifecycle == .running {
                    let g = try #require(f.generatedAt)
                    #expect(f.publisherExpiresAt == g.addingTimeInterval(30))
                    for row in f.rows where row.value.isKnown {
                        #expect(row.validUntil != nil, "\(scenario) \(row.id)")
                        #expect(row.value != .malformed, "\(scenario) \(row.id)")
                    }
                    if case .verdict(let v) = f.row("status")?.value, let c = v.counts?.health.complete {
                        #expect(v.configured == c.up + c.warning + c.down + c.unknown)
                    }
                }
            }
        }
    }

    @Test func listsServersWhenAsked() {
        var s = Settings()
        s.sections.servers = true
        let asked = TemplateCompiler().request(for: s, revision: 1, listServers: true)
        let r = FixtureEngine.reading(.incidents, request: asked, origin: t, after: 4)
        guard let row = r.row(TemplateCompiler.RowID.servers), case .servers(let list) = r.lastValue(of: row) else {
            Issue.record("no server list")
            return
        }
        #expect(list.count == 11)
        #expect(list.first { $0.id == "bwh-la" }?.note == "affected")
        let plain = FixtureEngine.reading(.incidents, request: TemplateCompiler().request(for: s, revision: 1), origin: t, after: 4)
        #expect(plain.row(TemplateCompiler.RowID.servers) == nil)
    }

    @Test func replaysAgainstTheClock() async {
        let clock = ManualClock(t)
        let e = FixtureEngine(scenario: .clear, clock: clock, tick: nil)
        var it = e.start(request()).makeAsyncIterator()
        // Running, then the frames at or before the anchor, shifted to now.
        let first = await take(4, from: &it)
        guard case .status(.running) = first[0] else { Issue.record("not running"); return }
        let f = frames(first)
        #expect(f.map(\.generatedAt) == [t.addingTimeInterval(-20), t.addingTimeInterval(-10), t])
        #expect(f.map(\.sequence) == [1, 2, 3])
        #expect(f.allSatisfy { $0.requestID == "settings-1" })
        clock.advance(9)
        e.pump()
        clock.advance(1)
        e.pump()
        let next = frames(await take(1, from: &it))
        #expect(next.first?.generatedAt == t.addingTimeInterval(10))
        #expect(next.first?.sequence == 4)
        // Looping: frames keep coming past the fixture's end.
        clock.advance(120)
        e.pump()
        let more = frames(await take(12, from: &it))
        #expect(more.count == 12)
        #expect(zip(more, more.dropFirst()).allSatisfy { ($0.sequence ?? 0) < ($1.sequence ?? 0) })
        #expect(zip(more, more.dropFirst()).allSatisfy { ($0.generatedAt ?? t) < ($1.generatedAt ?? t) })
        await e.stop()
    }

    @Test func fitsFramesToTheRequest() async {
        let clock = ManualClock(t)
        let e = FixtureEngine(scenario: .incidents, clock: clock, tick: nil)
        var it = e.start(request(limit: 3)).makeAsyncIterator()
        let f = frames(await take(4, from: &it)).last!
        #expect(f.rows.map(\.id) == ["status", "seen", "attention", "apps", "server-1", "server-2", "mac"])
        guard case .attention(let a) = f.row("attention")?.value else { Issue.record("no attention"); return }
        #expect(a.items.count == 3)
        #expect(a.total == 17)
        #expect(f.row("attention")?.limit == 3)
        guard case .serverCard(let c) = f.row("server-2")?.value else { Issue.record("no card"); return }
        #expect(c.id == "bwh-la")
        #expect(c.note == "affected")

        // A new request takes effect at once, with its own ID.
        try? await e.update(request("settings-2", limit: 5, nodes: ["old-box"], mac: nil))
        let g = frames(await take(1, from: &it)).first!
        #expect(g.requestID == "settings-2")
        #expect(g.rows.map(\.id) == ["status", "seen", "attention", "apps", "server-1"])
        #expect(g.row("server-1")?.value == RowValue.none)
        #expect(g.row("server-1")?.reason == "entity_missing")
        guard case .attention(let b) = g.row("attention")?.value else { Issue.record("no attention"); return }
        #expect(b.items.count == 5)
        await e.stop()
    }

    @Test func staleStopsWritingAndTheLeaseLapses() async {
        let clock = ManualClock(t)
        let e = FixtureEngine(scenario: .stale, clock: clock, tick: nil)
        var it = e.start(request()).makeAsyncIterator()
        var p = ReaderPolicy()
        for ev in await take(8, from: &it) { if case .frame(let f, _) = ev { p.receive(f, at: clock.now()) } }
        #expect(p.evaluate(at: clock.now()).isLive)
        clock.advance(29)
        #expect(e.pump())
        #expect(p.evaluate(at: clock.now()).isLive)
        clock.advance(1)
        #expect(p.evaluate(at: clock.now()).availability == .leaseExpired(since: t.addingTimeInterval(30)))
        #expect(p.lastKnown?.text == "5 INCIDENTS")
        await e.stop()
    }

    @Test func offlineKeepsTheLastSnapshotAsHistory() async {
        let clock = ManualClock(t)
        let e = FixtureEngine(scenario: .offline, clock: clock, tick: nil)
        var it = e.start(request()).makeAsyncIterator()
        var p = ReaderPolicy()
        // running + the clear frame 3 min ago + 18 unreachable frames
        for ev in await take(20, from: &it) { if case .frame(let f, _) = ev { p.receive(f, at: clock.now()) } }
        let r = p.evaluate(at: clock.now())
        #expect(r.isLive)
        #expect(r.row("status")?.status == .withheld(.noValue))
        #expect(r.row("status")?.row.reason == "source_unavailable")
        #expect(r.lastKnown?.state == "clear")
        #expect(r.lastKnown?.at == t.addingTimeInterval(-180))
        await e.stop()
    }

    @Test func stoppedEndsTheSource() async {
        let clock = ManualClock(t)
        let e = FixtureEngine(scenario: .stopped, clock: clock, tick: nil)
        var it = e.start(request()).makeAsyncIterator()
        _ = await take(5, from: &it)
        clock.advance(5)
        #expect(e.pump())
        let end = await take(2, from: &it)
        #expect(frames(end).first?.lifecycle == .stopped)
        guard case .status(.stopped) = end.last else { Issue.record("not stopped"); return }
    }

    @Test func errorFramesArriveWithTheirRequestID() async {
        let clock = ManualClock(t)
        let e = FixtureEngine(scenario: .errorFrame, clock: clock, tick: nil)
        var it = e.start(request()).makeAsyncIterator()
        _ = await take(4, from: &it)
        clock.advance(5)
        e.pump()
        let err = frames(await take(1, from: &it)).first
        #expect(err?.lifecycle == .error)
        #expect(err?.requestID == "fixture-refused")
        #expect(err?.error?.code == "invalid_request")
        await e.stop()
    }

    @Test func stopWritesAFinalFrame() async {
        let clock = ManualClock(t)
        let e = FixtureEngine(scenario: .clear, clock: clock, tick: nil)
        let stream = e.start(request())
        await e.stop()
        var all: [EngineEvent] = []
        for await ev in stream { all.append(ev) }
        #expect(frames(all).last?.lifecycle == .stopped)
        guard case .status(.stopped) = all.last else { Issue.record("not stopped"); return }
    }

    @Test func runsOnTheSystemClock() async throws {
        let e = FixtureEngine(scenario: .clear, tick: .milliseconds(20))
        var it = e.start(request()).makeAsyncIterator()
        let first = await take(4, from: &it)
        let f = try #require(frames(first).last)
        #expect(abs(f.generatedAt!.timeIntervalSinceNow) < 2)
        await e.stop()
    }
}
