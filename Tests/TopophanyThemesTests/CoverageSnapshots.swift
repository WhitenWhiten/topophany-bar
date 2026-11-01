import Foundation
import SwiftUI
import Testing
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

@MainActor @Suite(.serialized) struct CoverageSnapshots {
    @Test func scopedStatus() throws {
        for language in ["en", "zh-Hans", "ja"] {
            try L10n.with(language) {
                var model = previewPanel(.clear)
                model.status.coverage = try JSONDecoder().decode(ServiceCoverage.self, from: Data(#"{"observer":"home","services":23,"known":3}"#.utf8))
                #expect(model.status.coverageText != nil)
                #expect(!model.status.coverageIsComplete && model.status.coverageHelp != nil)
                // Topophany 1.5.2's own line, so the panel and the TUI agree.
                if language == "en" { #expect(model.status.coverageText == "Service availability: 3/23 known") }
                for theme in [ThemeStore.native, ThemeStore.terminal] {
                    let ctx = RenderContext(theme: theme, colorScheme: .dark)
                    try snapshot("coverage-\(language)-\(theme.id)", OnDesktop(dark: true) {
                        Renderers.renderer(for: theme).panel(model, context: ctx)
                    })
                }
                model.status.kind = .blind(.cached)
                #expect(model.status.coverageText == nil)
            }
        }
    }
}
