import AppKit
import Observation
import SwiftUI
import Synchronization
import Testing
@testable import TopophanyThemes

@MainActor
@Suite struct PanelScrollTests {
    @Test func scrollingOnlyInvalidatesAtEdges() {
        let state = PanelScrollState()
        state.update(PanelLeap(offset: 100, content: 2000, visible: 700))
        let invalidated = Mutex(false)
        withObservationTracking {
            _ = state.atTop
            _ = state.atEnd
        } onChange: {
            invalidated.withLock { $0 = true }
        }

        // An animation's intermediate frames keep the panel's content
        // intact, but the next key press must use the latest position.
        for offset in stride(from: 110.0, through: 600.0, by: 10) {
            state.update(PanelLeap(offset: offset, content: 2000, visible: 700))
        }
        #expect(!invalidated.withLock { $0 })
        #expect(state.target(panel: 1000) == 1100)

        state.update(PanelLeap(offset: 1300, content: 2000, visible: 700))
        #expect(invalidated.withLock { $0 })
        #expect(state.atEnd)
        #expect(state.target(panel: 1000) == 0)
    }

    @Test func edgesFollowScrollingAndResizing() {
        let state = PanelScrollState()
        state.update(PanelLeap(offset: 0, content: 2000, visible: 700))
        #expect(state.atTop && !state.atEnd)
        state.update(PanelLeap(offset: 400, content: 2000, visible: 700))
        #expect(!state.atTop && !state.atEnd)
        // Resizing can reveal the end without moving the content.
        state.update(PanelLeap(offset: 400, content: 2000, visible: 1600))
        #expect(!state.atTop && state.atEnd)
        state.update(PanelLeap(offset: 0, content: 2000, visible: 700))
        #expect(state.atTop && !state.atEnd)
        #expect(state.target(panel: 1000) == 500)
    }

    @Test func longReturnsKeepThePaceOfDownwardLeaps() {
        let down = PanelLeap(offset: 0, content: 2000, visible: 700)
        let up = PanelLeap(offset: 1300, content: 2000, visible: 700)
        #expect(down.duration(panel: 1000) == 0.3)
        #expect(abs(up.duration(panel: 1000) - 0.78) < 1e-9)
        let downSpeed = abs(down.target(panel: 1000) - down.offset) / down.duration(panel: 1000)
        let upSpeed = abs(up.target(panel: 1000) - up.offset) / up.duration(panel: 1000)
        #expect(abs(downSpeed - upSpeed) < 1e-9)
        // A short viewport, rather than the full panel, limits each leap.
        #expect(PanelLeap(offset: 400, content: 700, visible: 300).duration(panel: 1000) == 0.4)
        #expect(PanelLeap(offset: 10_000, content: 10_700, visible: 700).duration(panel: 1000) == 0.9)
        #expect(PanelLeap().duration(panel: 1000).isFinite)
    }

    @Test func reducedMotionSkipsTheLeapAnimation() {
        let state = PanelScrollState()
        state.update(PanelLeap(offset: 1300, content: 2000, visible: 700))
        #expect(state.animation(panel: 1000, reduceMotion: true) == nil)
        #expect(state.animation(panel: 1000, reduceMotion: false) != nil)
    }

    @Test func rubberBandingAndShortContentNeverProduceNegativeTargets() {
        #expect(PanelLeap(offset: -80, content: 2000, visible: 700).target(panel: 1000) == 500)
        #expect(PanelLeap(offset: 50, content: 300, visible: 700).target(panel: 1000) == 0)
        #expect(PanelLeap(offset: -80, content: 300, visible: 700).target(panel: 1000) == 0)
        #expect(PanelLeap().target(panel: 1000) == 0)
    }

    /// Exercise SwiftUI's real binding and layout graph, not just the
    /// observation model. Scroll writebacks and edge crossings must leave
    /// expensive content intact in both directions.
    @Test func scrollingDoesNotReevaluateHostedContent() throws {
        let state = PanelScrollState()
        let counter = BodyCounter()
        let host = NSHostingView(rootView:
            PanelScroller(state: state, height: 300, panelHeight: 400, focus: nil, leaps: 0) {
                CountedContent(counter: counter)
            }
            .frame(width: 300)
        )
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        let initial = counter.count
        try #require(initial > 0)
        for offset in (0...30).map({ Double($0) * 50 }) + (0...30).reversed().map({ Double($0) * 50 }) {
            state.position.scrollTo(y: offset)
            state.update(PanelLeap(offset: offset, content: 1800, visible: 300))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        }
        #expect(counter.count == initial, "scrolling rebuilt its content \(counter.count - initial) times")
    }
}

@MainActor private final class BodyCounter {
    var count = 0
}

private struct CountedContent: View {
    var counter: BodyCounter

    var body: some View {
        let _ = { counter.count += 1 }()
        Text("Panel content").frame(width: 300, height: 1800)
    }
}
