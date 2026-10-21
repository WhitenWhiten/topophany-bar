import Observation
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
}
