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

    @Test func checkGrids() throws {
        // 68 checks fill four rows of a small widget's column.
        let small = try #require(CheckGrid.cells(68, in: CGSize(width: 142, height: 34)))
        #expect(small.rows == 4 && small.columns == 17)
        #expect(small.size.width <= 142 + 1e-9 && small.size.height <= 34 + 1e-9)
        #expect(abs(small.side - small.width) < 1e-9)
        // A few checks keep one row, spread across it.
        let few = try #require(CheckGrid.cells(10, in: CGSize(width: 142, height: 34)))
        #expect(few.rows == 1 && few.side == 7.5)
        // Rows stay about as evenly spaced across as down.
        let mid = try #require(CheckGrid.cells(20, in: CGSize(width: 142, height: 34)))
        #expect(mid.rows == 1)
        // More marks than can be read: the stacked bar instead.
        #expect(CheckGrid.cells(400, in: CGSize(width: 142, height: 34)) == nil)
        #expect(CheckGrid.cells(0, in: CGSize(width: 142, height: 34)) == nil)
    }
}
