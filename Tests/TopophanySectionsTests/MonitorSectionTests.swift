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

    @Test func serviceWidgetHistoryIsNotSuppressedByCompactMonitoring() {
        var settings = Settings()
        settings.sections.services = true
        settings.sections.monitors = [.init(kind: .check, id: "runtime")]
        let request = TemplateCompiler().request(for: settings, revision: 1, widgets: .init(services: ["site"]), serviceCards: true)
        #expect(request.template.rows.first { $0.metric == "service.card" }?.history == nil)
        #expect(request.template.rows.first { $0.metric == "check.card" }?.history == false)
    }
}
