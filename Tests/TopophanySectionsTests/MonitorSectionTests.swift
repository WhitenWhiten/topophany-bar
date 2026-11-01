import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

@Suite struct MonitorSectionTests {
    func fixture() throws -> Frame {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/preview.ndjson")
        return try #require(FrameDecoder.frame(from: Data(contentsOf: url)))
    }

    @Test func pinnedCardsUseReportedEvidenceAndHideExpiredReadings() throws {
        let f = try fixture(), now = try #require(f.generatedAt)
        var policy = ReaderPolicy(); policy.receive(f, at: now)
        let pins: [MonitorPin] = [.init(kind: .check, id: "m-clash"), .init(kind: .link, id: "home-cf")]
        let cards = SectionBuilder.monitors(policy.evaluate(at: now), pins: pins + pins, expanded: [pins[1]])
        #expect(cards.count == 2)
        #expect(cards.map(\.focusID) == pins.map(\.id))
        #expect(cards[1].monitor?.expanded == true)
        #expect(cards[1].mark == .up)
        #expect(cards[0].monitor?.reading.isEmpty == false)
        let stale = SectionBuilder.monitors(policy.evaluate(at: now.addingTimeInterval(600)), pins: pins)
        #expect(stale.count == 2)
        #expect(stale.allSatisfy { $0.isWithheld && $0.mark == .offline && $0.monitor?.reading == "" })
        #expect(stale.flatMap { $0.monitor?.checks ?? [] }.allSatisfy { $0.reading.isEmpty && $0.code.isEmpty && $0.p50 == nil })
    }

    @Test func settingsKeepTypedPinsAndDirectDoesNotRequestThem() throws {
        var settings = Settings()
        settings.sections.services = true
        settings.sections.monitors = [.init(kind: .check, id: "runtime"), .init(kind: .link, id: "tunnel")]
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.sections.monitors == settings.sections.monitors)
        let compiler = TemplateCompiler()
        let r = compiler.request(for: settings, revision: 1)
        #expect(r.template.rows.contains { $0.metric == "check.card" && $0.select?.check == "runtime" })
        #expect(r.template.rows.contains { $0.metric == "link.card" && $0.select?.link == "tunnel" })
        #expect(r.template.rows.filter { $0.metric == "check.card" || $0.metric == "link.card" }.allSatisfy { $0.history == false })
        let detailed = compiler.request(for: settings, revision: 2, serviceCards: true,
                                       monitorHistory: [settings.sections.monitors[0]])
        #expect(detailed.template.rows.first { $0.metric == "check.card" }?.history == true)
        #expect(detailed.template.rows.first { $0.metric == "link.card" }?.history == false)
        settings.topo.source = "direct"; settings.topo.profile = "test"
        #expect(!compiler.request(for: settings, revision: 2).template.rows.contains { $0.metric == "check.card" || $0.metric == "link.card" })
    }

    @Test func checkWidgetsAskForTheirCardsWithHistory() {
        var settings = Settings()
        settings.sections.services = true
        settings.sections.monitors = [.init(kind: .check, id: "runtime")]
        let widgets = TemplateCompiler.WidgetNeeds(monitors: [.init(kind: .check, id: "runtime"), .init(kind: .link, id: "tunnel"),
                                                              .init(kind: .link, id: "tunnel"), .init(kind: .check, id: "bad id")])
        let rows = TemplateCompiler().request(for: settings, revision: 1, widgets: widgets).template.rows
        // A pinned check is asked for once, with the history its widget draws.
        let checks = rows.filter { $0.metric == "check.card" }
        #expect(checks.count == 1 && checks.first?.history == true && checks.first?.id == "monitor-1")
        let links = rows.filter { $0.metric == "link.card" }
        #expect(links.count == 1 && links.first?.history == true && links.first?.id == "widget-monitor-1")
        // The panel needn't pin anything for a widget to have its card.
        settings.sections.services = false
        let alone = TemplateCompiler().request(for: settings, revision: 2, widgets: widgets).template.rows
        #expect(alone.filter { $0.metric == "check.card" || $0.metric == "link.card" }.map(\.id) == ["widget-monitor-1", "widget-monitor-2"])
        // Direct mode reads no checks.
        settings.topo.source = "direct"; settings.topo.profile = "test"
        #expect(!TemplateCompiler().request(for: settings, revision: 3, widgets: widgets).template.rows.contains { $0.metric.hasSuffix(".card") && $0.metric != "server.card" })
    }

    @Test func serviceWidgetHistoryIsNotSuppressedByCompactMonitoring() {
        var settings = Settings()
        settings.sections.services = true
        settings.sections.monitors = [.init(kind: .check, id: "runtime")]
        let request = TemplateCompiler().request(for: settings, revision: 1, widgets: .init(services: ["site"]), serviceCards: true)
        #expect(request.template.rows.first { $0.metric == "service.card" }?.history == nil)
        #expect(request.template.rows.first { $0.metric == "check.card" }?.history == false)
    }

    @Test func affectedLinkKeepsItsHealthButShowsImpact() throws {
        var frame = try fixture()
        let now = try #require(frame.generatedAt)
        let index = try #require(frame.rows.firstIndex { $0.metric == "link.card" })
        guard case .linkCard(var link) = frame.rows[index].value else { Issue.record("missing link"); return }
        link.summary.affected = true
        frame.rows[index].value = .linkCard(link)
        var policy = ReaderPolicy(); policy.receive(frame, at: now)
        let card = try #require(SectionBuilder.monitors(policy.evaluate(at: now), pins: [.init(kind: .link, id: "home-cf")]).first)
        #expect(link.summary.health == .up)
        #expect(card.mark == .degraded && card.pill.mark == .degraded)
        #expect(card.pill.text == Pill.state("affected", health: .up).text)
    }
}
