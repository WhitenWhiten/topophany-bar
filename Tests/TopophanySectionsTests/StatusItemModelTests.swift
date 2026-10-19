import Foundation
import Testing
@testable import TopophanySections
import TopophanyEngine
import TopophanyKit

@Suite struct StatusItemModelTests {
    init() { L10n.force("en") }

    func item(_ status: StatusSection) -> StatusItemModel {
        StatusItemModel(status: status, appearance: Settings.Appearance.MenuBar())
    }

    func blind(_ engine: EngineCondition) -> StatusSection {
        SectionBuilder.panel(PanelInput(reading: ReaderPolicy().evaluate(at: origin), engine: engine, settings: settings())).status
    }

    /// Only a current verdict may turn; `topo` starting, or about to start
    /// again, is under way; anything else rests.
    @Test func activity() {
        #expect(item(panel(.clear).status).activity == .live)
        #expect(item(panel(.incidents).status).activity == .live)
        #expect(item(panel(.incomplete).status).activity == .live)
        #expect(item(panel(.offline).status).activity == .resting)
        #expect(item(blind(.starting)).activity == .connecting)
        #expect(item(blind(.restarting(at: origin.addingTimeInterval(5)))).activity == .connecting)
        #expect(item(blind(.stopped)).activity == .resting)
        #expect(item(blind(.notFound)).activity == .resting)
        #expect(item(panel(.clear).status).motion)
    }

    /// Only a change that needs more attention ripples: a worse mark, or
    /// more needing attention under the same one.
    @Test func moreAttention() {
        let clear = item(panel(.clear).status)
        let degraded = item(panel(.degraded).status)
        let incidents = item(panel(.incidents).status)
        let incomplete = item(panel(.incomplete).status)
        #expect(degraded.needsMoreAttention(than: clear))
        #expect(incidents.needsMoreAttention(than: degraded))
        #expect(degraded.needsMoreAttention(than: incomplete))
        #expect(!clear.needsMoreAttention(than: incidents))
        #expect(!degraded.needsMoreAttention(than: incidents))
        #expect(!incomplete.needsMoreAttention(than: clear))
        var fewer = incidents
        fewer.count = 3
        #expect(incidents.needsMoreAttention(than: fewer))
        #expect(!fewer.needsMoreAttention(than: incidents))
        #expect(!incidents.needsMoreAttention(than: incidents))
    }
}
