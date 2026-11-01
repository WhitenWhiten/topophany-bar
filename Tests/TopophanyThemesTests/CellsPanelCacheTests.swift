import Foundation
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor
@Suite struct CellsPanelCacheTests {
    @Test func monitorDisclosureRegionsSurviveReuseAndMoving() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/preview.ndjson")
        let frame = try #require(FrameDecoder.frame(from: Data(contentsOf: url)))
        let now = try #require(frame.generatedAt)
        var policy = ReaderPolicy(); policy.receive(frame, at: now)
        let pin = MonitorPin(kind: .link, id: "home-cf")
        var model = previewPanel(.clear)
        model.sections.append(.services(SectionBuilder.monitors(policy.evaluate(at: now), pins: [pin], expanded: [pin])))
        let cache = CellsPanelCache(), ctx = RenderContext(theme: ThemeStore.terminal)
        for _ in 0..<2 {
            let cached = CellsPanel.scene(model, ctx: ctx, cache: cache)
            let fresh = CellsPanel.scene(model, ctx: ctx)
            #expect(cached == fresh)
            #expect(cached.regions[pin.id] != nil)
        }
        model.sections.reverse()
        #expect(CellsPanel.scene(model, ctx: ctx, cache: cache) == CellsPanel.scene(model, ctx: ctx))
    }

    @Test func reusedSectionsPreserveDrawingAndInteractionRegions() {
        let cache = CellsPanelCache()
        var model = MapSnapshots().panel(.incidents)
        for language in ["en", "ja", "zh-Hans"] {
            L10n.with(language) {
                for theme in ThemeStore.builtIn.filter({ $0.renderer == .cells }) {
                    for focus in [nil, "map", "attention:more", "seen:home", nil] as [String?] {
                        let ctx = RenderContext(theme: theme, focus: focus, maxHeight: 600)
                        // Populate, hit, then vary the footer independently.
                        for hover in [nil, nil, "quit", "settings"] as [String?] {
                            let cached = CellsPanel.scene(model, ctx: ctx, hover: hover, cache: cache)
                            let fresh = CellsPanel.scene(model, ctx: ctx, hover: hover)
                            let same = cached == fresh
                            #expect(same, "\(language), \(theme.id), focus \(focus ?? "none"), hover \(hover ?? "none")")
                        }
                    }
                    // A section moving to another absolute y must invalidate
                    // its cached coordinates, including the map's hit area.
                    model.sections.reverse()
                    let ctx = RenderContext(theme: theme, focus: "map", maxHeight: 600)
                    let same = CellsPanel.scene(model, ctx: ctx, cache: cache) == CellsPanel.scene(model, ctx: ctx)
                    #expect(same)
                }
            }
        }
    }
}
