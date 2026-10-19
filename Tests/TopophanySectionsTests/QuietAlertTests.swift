import Foundation
import Testing
@testable import TopophanySections
import TopophanyEngine
import TopophanyKit

/// Quieting the menu bar's alert: it holds until the verdict asks for more
/// attention, eases as it improves, and ends when it clears.
@Suite struct QuietAlertTests {
    init() { L10n.force("en") }

    func verdict(_ state: VerdictState, warning: Int = 0, down: Int = 0, incidents: Int = 0) -> StatusSection {
        let mark: Mark = switch state {
        case .clear: .up
        case .degraded: .degraded
        case .incidents, .down: .down
        default: .unknown
        }
        return StatusSection(kind: .verdict(state), mark: mark,
                             counts: HealthCounts(up: 60, warning: warning, down: down, unknown: 0), configured: 60 + warning + down,
                             incidents: incidents, now: origin)
    }

    var offline: StatusSection { StatusSection(kind: .blind(.leaseLapsed), mark: .offline, now: origin) }

    @Test func onlyAnAlertCanBeQuieted() {
        #expect(QuietAlert(verdict(.clear)) == nil)
        #expect(QuietAlert(verdict(.incomplete)) == nil)
        #expect(QuietAlert(offline) == nil)
        #expect(QuietAlert(verdict(.degraded, warning: 2)) == QuietAlert(mark: .degraded, count: 2))
        #expect(QuietAlert(verdict(.incidents, down: 5, incidents: 5)) == QuietAlert(mark: .down, count: 5))
    }

    @Test func holdsUntilItGetsWorse() throws {
        let q = try #require(QuietAlert(verdict(.degraded, warning: 2)))
        #expect(q.after(verdict(.degraded, warning: 2)) == q)
        #expect(q.after(verdict(.degraded, warning: 3)) == nil, "more under the same mark")
        #expect(q.after(verdict(.incidents, down: 1, incidents: 1)) == nil, "a worse mark")
        // Nothing current known is not worse, and it holds what it had.
        #expect(q.after(offline) == q)
        #expect(q.after(verdict(.incomplete)) == q)
    }

    @Test func easesAsItImproves() throws {
        let q = try #require(QuietAlert(verdict(.incidents, down: 5, incidents: 5)))
        let eased = try #require(q.after(verdict(.incidents, down: 2, incidents: 2)))
        #expect(eased == QuietAlert(mark: .down, count: 2))
        // Worse than now, though better than when it was quieted: it alerts.
        #expect(eased.after(verdict(.incidents, down: 3, incidents: 3)) == nil)
        let warn = try #require(q.after(verdict(.degraded, warning: 4)))
        #expect(warn.after(verdict(.down, down: 1)) == nil)
    }

    @Test func endsWhenItClears() throws {
        let q = try #require(QuietAlert(verdict(.degraded, warning: 2)))
        #expect(q.after(verdict(.clear)) == nil)
    }

    /// The item draws a quieted badge in its ink, says so to VoiceOver, and
    /// the panel offers to show it again; with status colors off there is
    /// nothing to quiet.
    @Test func itemAndPanel() throws {
        let p = panel(.incidents)
        let q = try #require(QuietAlert(p.status))
        var a = Settings.Appearance.MenuBar()
        let loud = StatusItemModel(status: p.status, appearance: a)
        let quiet = StatusItemModel(status: p.status, appearance: a, quiet: q)
        #expect(loud.tinted && !loud.quiet)
        #expect(!quiet.tinted && quiet.quiet)
        #expect(quiet.mark == loud.mark && quiet.count == loud.count && quiet.text == loud.text)
        #expect(quiet.accessibilityLabel == "Topophany: 5 incidents, quieted, updated 4 seconds ago")

        let reading = FixtureEngine.reading(.incidents, request: TemplateCompiler().request(for: settings(), revision: 1),
                                            origin: origin, after: 4)
        var s = settings()
        #expect(SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: s)).alert == .shown)
        #expect(SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: s, quiet: q)).alert == .quiet)
        s.appearance.menuBar.statusColors = false
        a.statusColors = false
        #expect(SectionBuilder.panel(PanelInput(reading: reading, engine: .running, settings: s, quiet: q)).alert == .unavailable)
        #expect(!StatusItemModel(status: p.status, appearance: a, quiet: q).quiet)
        #expect(panel(.clear).alert == .unavailable)
    }
}
