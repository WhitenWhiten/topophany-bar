import Testing
import TopophanySections
@testable import TopophanyThemes

@MainActor
@Suite struct CellsPanelCacheTests {
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
