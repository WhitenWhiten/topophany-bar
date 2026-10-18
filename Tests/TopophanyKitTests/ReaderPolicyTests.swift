import Foundation
import Testing
@testable import TopophanyKit

/// PROTOCOL.md §5, against a clock that moves only when told to.
@Suite struct ReaderPolicyTests {
    let t0 = Timestamp.parse("2026-10-18T13:30:00Z")!
    var clock: ManualClock { ManualClock(t0) }

    func verdict(_ state: String = "clear") -> RowValue {
        .verdict(Verdict(state: VerdictState(state), glyph: "●", text: "ALL CLEAR",
                         counts: VerdictCounts(health: HealthCounts(up: 68, warning: 0, down: 0, unknown: 0)),
                         configured: 68, incidents: 0, observers: ObserversLive(live: 11, all: 11)))
    }

    func frame(at g: Date, lease: TimeInterval = 30, sequence: UInt64 = 1, instance: String = "i1",
               statusValid: TimeInterval? = 15, rows extra: [Row] = []) -> Frame {
        let status = Row(id: "status", metric: "summary.verdict", value: verdict(), text: "ALL CLEAR", health: .up,
                         sampledAt: g, validUntil: statusValid.map { g.addingTimeInterval($0) })
        return Frame(instance: instance, sequence: sequence, generatedAt: g, publisherExpiresAt: g.addingTimeInterval(lease),
                     rows: [status] + extra)
    }

    @Test func waitsForTheFirstFrame() {
        let p = ReaderPolicy()
        #expect(p.evaluate(at: t0).availability == .waiting)
        #expect(p.evaluate(at: t0).rows.isEmpty)
    }

    @Test func currentWithinLeaseAndDeadline() {
        let c = clock
        var p = ReaderPolicy()
        p.sourceStarted()
        p.receive(frame(at: c.now()), at: c.now())
        let r = p.evaluate(at: c.now())
        #expect(r.availability == .live)
        #expect(r.row("status")?.isCurrent == true)
        #expect(r.row("status")?.value == verdict())
    }

    @Test func withholdsARowPastItsDeadline() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now()), at: c.now())
        c.advance(14.999)
        #expect(p.evaluate(at: c.now()).row("status")?.isCurrent == true)
        c.advance(0.001)
        let r = p.evaluate(at: c.now())
        #expect(r.availability == .live)
        #expect(r.row("status")?.status == .withheld(.expired))
        #expect(r.row("status")?.value == RowValue.none)
    }

    @Test func nothingIsCurrentPastTheLease() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now(), statusValid: 60), at: c.now())
        c.advance(30)
        let r = p.evaluate(at: c.now())
        #expect(r.availability == .leaseExpired(since: t0.addingTimeInterval(30)))
        #expect(r.row("status")?.status == .withheld(.unavailable))
        // The frame is kept for its metadata and the history it left.
        #expect(r.frame != nil)
        #expect(r.lastKnown?.text == "ALL CLEAR")
    }

    @Test func neverExtendsARowWithALaterLease() {
        let c = clock
        var p = ReaderPolicy()
        let first = frame(at: c.now(), statusValid: 15)
        p.receive(first, at: c.now())
        c.advance(10)
        // A renewal: a new lease, the status row unchanged, deadline and all.
        var renewal = first
        renewal.sequence = 2
        renewal.generatedAt = c.now()
        renewal.publisherExpiresAt = c.now().addingTimeInterval(30)
        p.receive(renewal, at: c.now())
        c.advance(5)
        let r = p.evaluate(at: c.now())
        #expect(r.availability == .live)
        #expect(r.row("status")?.status == .withheld(.expired))
    }

    @Test func aRowWithAValueAndNoDeadlineIsWithheld() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now(), statusValid: nil), at: c.now())
        #expect(p.evaluate(at: c.now()).row("status")?.status == .withheld(.expired))
    }

    @Test func aRowWithoutAValueIsUnknownNotZero() {
        let c = clock
        var p = ReaderPolicy()
        let missing = Row(id: "nyc", metric: "server.card", value: .none, text: "unknown", health: .unknown,
                          freshness: "unavailable", reason: "entity_missing", validUntil: nil)
        p.receive(frame(at: c.now(), rows: [missing]), at: c.now())
        #expect(p.evaluate(at: c.now()).row("nyc")?.status == .withheld(.noValue))
    }

    @Test func implausiblyFutureFramesAreUnavailable() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now().addingTimeInterval(301)), at: c.now())
        #expect(p.evaluate(at: c.now()).availability == .implausible)

        // Five minutes ahead is still plausible.
        var q = ReaderPolicy()
        q.receive(frame(at: c.now().addingTimeInterval(240), lease: 30), at: c.now())
        #expect(q.evaluate(at: c.now()).availability == .live)

        // A lease far beyond the clock is implausible even from a current frame.
        var l = ReaderPolicy()
        l.receive(frame(at: c.now(), lease: 3600), at: c.now())
        #expect(l.evaluate(at: c.now()).availability == .implausible)
    }

    @Test func implausiblyFutureRowsAreWithheld() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now(), statusValid: 400), at: c.now())
        #expect(p.evaluate(at: c.now()).row("status")?.status == .withheld(.implausible))

        let row = Row(id: "x", metric: "summary.verdict", value: verdict(), health: .up,
                      sampledAt: c.now().addingTimeInterval(600), validUntil: c.now().addingTimeInterval(10))
        var q = ReaderPolicy()
        q.receive(frame(at: c.now(), rows: [row]), at: c.now())
        #expect(q.evaluate(at: c.now()).row("x")?.status == .withheld(.implausible))
    }

    @Test func missingTimesAreUnavailable() {
        let c = clock
        var p = ReaderPolicy()
        var f = frame(at: c.now())
        f.publisherExpiresAt = nil
        p.receive(f, at: c.now())
        #expect(p.evaluate(at: c.now()).availability == .implausible)
    }

    @Test func errorFramesAreNeverContent() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now()), at: c.now())
        let err = Frame(requestID: "settings-2", lifecycle: .error, generatedAt: c.now(),
                        publisherExpiresAt: c.now().addingTimeInterval(30), rows: [],
                        error: .init(code: "invalid_request", message: "row attention: limit must be 1..20"))
        p.receive(err, at: c.now())
        let r = p.evaluate(at: c.now())
        #expect(r.availability == .live)
        #expect(r.row("status")?.isCurrent == true)
        #expect(r.error?.code == "invalid_request")
        #expect(r.errorRequestID == "settings-2")
        // The kept frame still lapses on its own deadlines.
        c.advance(30)
        #expect(p.evaluate(at: c.now()).availability == .leaseExpired(since: t0.addingTimeInterval(30)))
        // A running frame clears the error.
        p.receive(frame(at: c.now(), sequence: 2), at: c.now())
        #expect(p.evaluate(at: c.now()).error == nil)
    }

    @Test func theSourceEndingIsUnavailableAtOnce() {
        let c = clock
        var p = ReaderPolicy()
        p.sourceStarted()
        p.receive(frame(at: c.now()), at: c.now())
        c.advance(1)
        p.sourceEnded(at: c.now())
        let r = p.evaluate(at: c.now())
        #expect(r.availability == .sourceEnded(since: t0.addingTimeInterval(1)))
        #expect(r.row("status")?.isCurrent == false)
        // A new process stays unavailable until its first frame.
        p.sourceStarted()
        #expect(p.evaluate(at: c.now()).availability == .sourceEnded(since: t0.addingTimeInterval(1)))
        p.receive(frame(at: c.now(), instance: "i2"), at: c.now())
        #expect(p.evaluate(at: c.now()).availability == .live)
    }

    @Test func aStoppedFrameEndsEverything() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now()), at: c.now())
        p.receive(Frame(lifecycle: .stopped, generatedAt: c.now(), publisherExpiresAt: c.now(), rows: []), at: c.now())
        #expect(p.evaluate(at: c.now()).availability == .stopped(since: t0))
        p.sourceEnded(at: c.now())
        #expect(p.evaluate(at: c.now()).availability == .stopped(since: t0))
    }

    @Test func ignoresSequenceRegressionsWithinAnInstance() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now(), sequence: 5), at: c.now())
        p.receive(frame(at: c.now().addingTimeInterval(-60), sequence: 4), at: c.now())
        #expect(p.evaluate(at: c.now()).frame?.sequence == 5)
        p.receive(frame(at: c.now(), sequence: 1, instance: "i2"), at: c.now())
        #expect(p.evaluate(at: c.now()).frame?.instance == "i2")
    }

    @Test func lastKnownOnlyFromACurrentVerdict() {
        let c = clock
        var p = ReaderPolicy()
        p.receive(frame(at: c.now(), statusValid: nil), at: c.now())
        #expect(p.lastKnown == nil)
        p.receive(frame(at: c.now(), sequence: 2), at: c.now())
        #expect(p.lastKnown?.state == "clear")
        #expect(p.lastKnown?.at == t0)
        // A frame that arrives late is still history from when it was made.
        var late = ReaderPolicy()
        late.receive(frame(at: c.now().addingTimeInterval(-180)), at: c.now())
        #expect(late.evaluate(at: c.now()).availability == .leaseExpired(since: t0.addingTimeInterval(-150)))
        #expect(late.lastKnown?.at == t0.addingTimeInterval(-180))
    }

    @Test func schemaOtherThanOneIsUnsupported() {
        let c = clock
        var p = ReaderPolicy()
        var f = frame(at: c.now())
        f.schema = 2
        p.receive(f, at: c.now())
        #expect(p.evaluate(at: c.now()).availability == .unsupported)
    }
}
