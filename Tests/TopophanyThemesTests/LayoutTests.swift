import Foundation
import Testing
@testable import TopophanyThemes

/// The arithmetic behind layouts that snapshots only show.
@Suite struct LayoutTests {
    @Test func routesKeepBothEnds() {
        let route = ["Primary BandwagonHost", "Oracle Exit A"]
        #expect(CellText.route(route, 40) == "Primary BandwagonHost → Oracle Exit A")
        // The shorter end keeps its width while it fits half; the other
        // gets the rest.
        #expect(CellText.route(route, 30) == "Primary Bandw… → Oracle Exit A")
        #expect(CellText.route(route, 17) == "Primar… → Oracle…")
        #expect(CellText.width(CellText.route(route, 17)) <= 17)
        // A cut never ends in a space; the cell it frees goes on.
        #expect(CellText.route(["Relay contrast", "BandwagonHost LA"], 17) == "Relay… → Bandwag…")
        // Too narrow for every part: the whole title, cut at its end.
        #expect(CellText.route(route, 7) == "Primar…")
        #expect(CellText.route(["Direct entry to BandwagonHost"], 17) == "Direct entry to…")
    }
}
