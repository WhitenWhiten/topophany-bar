import CoreGraphics
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// The map's framing, as the TUI's geo map frames it; its virtual view's
/// cards, apart; and how the panel's map is magnified and moved.
@MainActor
@Suite struct MapLayoutTests {
    init() { L10n.force("en") }

    typealias C = MapSection.Coordinate
    static let tokyo = C(lat: 35.68, lon: 139.77), honolulu = C(lat: 21.31, lon: -157.86), seattle = C(lat: 47.61, lon: -122.33)
    static let newYork = C(lat: 40.71, lon: -74.01), frankfurt = C(lat: 50.11, lon: 8.68)
    static let points = [tokyo, honolulu, seattle, newYork, frankfurt]

    /// Fit takes the smallest arc holding every place, Tokyo to Frankfurt
    /// across the Pacific, and folds the gaps wider than 60°: the ocean
    /// past Tokyo and the Atlantic, each to a seam, as the TUI does.
    @Test func fitFoldsWideGaps() throws {
        let size = CGSize(width: 330, height: 172)
        let v = GeoView.framing(Self.points, width: size.width, height: size.height, frame: .fit)
        #expect(v.folds.count == 2)
        #expect(v.seams.map(\.degrees) == [32, 53])
        let xs = Self.points.map { v.project($0).x }
        #expect(xs == xs.sorted(), "west to east across the Pacific")
        for p in Self.points.map(v.project) {
            #expect(p.x > 0 && p.x < size.width && p.y > 0 && p.y < size.height)
        }
        // A seam is blank, and the rest of the map maps back.
        for s in v.seams { #expect(v.at(s.x, size.height / 2) == nil) }
        let back = try #require(v.at(v.project(Self.seattle).x, v.project(Self.seattle).y))
        // Its longitude east of the map's west edge, a turn of the world aside.
        let turns = (back.lon - Self.seattle.lon) / 360
        #expect(abs(back.lat - Self.seattle.lat) < 1e-6 && abs(turns - turns.rounded()) < 1e-6)
    }

    /// World shows the whole world once, centred on the places, unfolded.
    @Test func worldShowsItAll() {
        let v = GeoView.framing(Self.points, width: 330, height: 172, frame: .world)
        #expect(v.folds.isEmpty)
        #expect(v.x1 - v.x0 >= 359.9)
        for p in Self.points.map(v.project) { #expect(p.x >= 0 && p.x <= 330 && p.y >= 0 && p.y <= 172) }
        // Nothing to place: the world, centred on Europe.
        #expect(GeoView.framing([], width: 330, height: 172, frame: .fit).folds.isEmpty)
    }

    @Test func smallestArc() {
        let (centre, span) = GeoView.lonBounds([170, -170])
        #expect(abs(span - 20) < 1e-9)
        #expect(abs(abs(centre) - 180) < 1e-9)
        #expect(GeoView.lonBounds([121.47, -118.24]).span < 125, "Shanghai and Los Angeles span the Pacific")
    }

    /// Nearby places share a site until magnified apart.
    @Test func sitesMergeUntilMagnified() throws {
        let m = try #require(MapSnapshots().panel(.incidents).map)
        let size = CGSize(width: 330, height: 172)
        let framed = GeoScene(m, size: size)
        #expect(framed.sites.contains { $0.title == "San Jose · Los Angeles" })
        let anchor = framed.view.project(try #require(MapPlaces.coordinate(for: "Los Angeles")))
        let close = GeoScene(m, size: size, transform: MapTransform().zoomed(by: 4, about: anchor))
        #expect(close.sites.contains { $0.title == "San Jose" } && close.sites.contains { $0.title == "Los Angeles" })
        // Every mark is topo's: a site's is its worst node's.
        #expect(framed.sites.first { $0.title.contains("Los Angeles") }?.mark == .degraded)
    }

    /// The virtual view's cards never sit on one another, at the panel's
    /// size and every widget's, in both looks.
    @Test func virtualCardsApart() throws {
        let m = try #require(MapSnapshots().panel(.incidents, .virtual).map)
        let cell = CellMetrics.panel.cell
        let cells = VirtualScene.Metrics(title: 15, row: 15, padX: cell, padY: 5, pill: 15, mark: 2 * cell, indent: 2 * cell,
                                         minWidth: 8 * cell, maxWidth: 22 * cell, colGap: 3 * cell, cardGap: 7, margin: cell,
                                         chipMark: 1.5 * cell, compactGap: 2 * cell, tiles: false)
        for size in [CGSize(width: 330, height: 172), CGSize(width: 164, height: 120), CGSize(width: 344, height: 120),
                     CGSize(width: 344, height: 290), CGSize(width: 704, height: 290)] {
            for metrics in [CardsMapPainter.virtualMetrics, cells] {
                let s = VirtualScene(m, size: size, metrics: metrics) { text, _ in Double(text.count) * 6.5 }
                #expect(s.cards.count >= m.places.count)
                for (i, a) in s.cards.enumerated() {
                    for b in s.cards[(i + 1)...] {
                        #expect(!a.rect.insetBy(dx: 0.5, dy: 0.5).intersects(b.rect), "\(a.title) on \(b.title) at \(size)")
                    }
                }
            }
        }
    }

    @Test func viewportZoomsAndMoves() {
        let v = MapViewport()
        v.layout(CGSize(width: 300, height: 150))
        v.zoom(by: 0.5)
        #expect(v.zoom == 1 && !v.isZoomed, "never smaller than the framing")
        v.zoom(by: 100)
        #expect(v.zoom == v.maxZoom)
        // Magnified about a point, that point stays put.
        v.reset()
        v.zoom(by: 2, at: CGPoint(x: 75, y: 50))
        #expect(v.transform.apply(CGPoint(x: 75, y: 50)) == CGPoint(x: 75, y: 50))
        // Moved no further than the map's edges.
        v.pan(by: CGSize(width: 10_000, height: -10_000))
        #expect(v.transform.offset == CGPoint(x: 0, y: -150))
        // A step out that would leave it barely magnified goes back.
        v.reset()
        v.step(in: true)
        v.step(in: true)
        #expect(abs(v.zoom - 2.25) < 1e-9)
        v.step(in: false)
        v.step(in: false)
        #expect(v.zoom == 1)
        // A map drawn in dots moves by points.
        let dots = MapViewport()
        dots.layout(CGSize(width: 92, height: 36), unit: CGSize(width: 3.6, height: 3.75))
        dots.zoom(by: 2, at: CGPoint(x: 0, y: 0))
        dots.pan(by: CGSize(width: -36, height: 0))
        #expect(abs(dots.transform.offset.x + 10) < 1e-9)
    }
}
