import Testing
@testable import TopophanyThemes

@Suite struct StatusItemTurnTests {
    func spun() -> StatusItemTurn {
        var t = StatusItemTurn()
        for _ in 0..<60 { t.advance(by: 1.0 / 15, turning: true) }
        return t
    }

    /// From rest to full speed in `spinUp`, then steady.
    @Test func spinsUp() {
        var t = StatusItemTurn()
        t.advance(by: 0.1, turning: true)
        #expect(t.velocity > 0 && t.velocity < StatusItemTurn.speed)
        #expect(spun().velocity == StatusItemTurn.speed)
    }

    /// It slows, never braking harder than from full speed in `spinDown`,
    /// and comes to rest on a whole step within a step of where braking
    /// that hard would stop it.
    @Test func landsOnAWholeStep() {
        for start in [0.0, 0.3, 0.77] {
            var t = spun()
            t.run(for: start / StatusItemTurn.speed)
            let from = t.phase
            var last = t.velocity
            var ticks = 0
            while t.isMoving, ticks < 10_000 {
                t.advance(by: 1.0 / 60, turning: false)
                #expect(t.velocity <= last)
                #expect((last - t.velocity) * 60 <= StatusItemTurn.speed / StatusItemTurn.spinDown + 1e-9)
                last = t.velocity
                ticks += 1
            }
            let natural = StatusItemTurn.speed * StatusItemTurn.spinDown / 2
            #expect(!t.isMoving)
            #expect(t.phase == t.phase.rounded())
            #expect(t.phase - from >= natural - 1e-9 && t.phase - from < natural + 1)
        }
    }

    /// A stalled clock moves it no further than a quarter second would.
    @Test func stallsDontJump() {
        var t = spun()
        let p = t.phase
        t.advance(by: 30, turning: true)
        #expect(t.phase - p <= StatusItemTurn.speed * 0.25 + 1e-9)
    }

    /// Played by the system meanwhile, it runs on at full speed; at rest it
    /// sits on a whole step.
    @Test func runsOnAndRests() {
        var t = StatusItemTurn()
        t.run(for: 2.4)
        #expect(t.velocity == StatusItemTurn.speed)
        #expect(abs(t.phase - 2.4 * StatusItemTurn.speed) < 1e-9)
        t.run(for: 0.3)
        t.rest()
        #expect(!t.isMoving && t.phase == t.phase.rounded())
    }
}
