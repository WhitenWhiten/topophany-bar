import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

/// Service cards as Topophany's preview scenario 10 sends them, with the
/// Services tab's assessment and the reasons availability is unknown.
@Suite struct AssessmentTests {
    func reading(at offset: TimeInterval = 0) throws -> (Reading, Date) {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/Monitoring/assessment.ndjson")
        let line = try Data(contentsOf: url)
        let f = try #require(FrameDecoder.frame(from: line))
        let now = try #require(f.generatedAt)
        var p = ReaderPolicy(); p.receive(f, line: line, at: now)
        return (p.evaluate(at: now.addingTimeInterval(offset)), now)
    }

    @Test func anAccessFailureIsNotAnOutageByItself() throws {
        try L10n.with("en") {
            let (r, _) = try reading()
            let cards = SectionBuilder.services(r, ids: ["memos", "blog", "home-rproxy"])
            let memos = try #require(cards.first { $0.id == "memos" }?.scope)
            #expect(memos.conclusion == "Unreachable from where it’s checked; not an outage by itself")
            #expect(memos.detail == "app unknown · path down · workers up")
            #expect(memos.hints == ["Checked from one place only: add a local health check"])
            #expect(memos.mark == .down)
            let blog = try #require(cards.first { $0.id == "blog" }?.scope)
            #expect(blog.detail.hasSuffix("workers partial"))
            // Up, from local and remote evidence: the pill says it all.
            #expect(cards.first { $0.id == "home-rproxy" }?.scope == nil)
        }
    }

    @Test func theAssessmentKeepsItsOwnDeadline() throws {
        let (r, now) = try reading()
        let row = try #require(r.rows.first { $0.row.select?.service == "memos" })
        guard case .serviceCard(let card) = row.value else { Issue.record("no card"); return }
        let assessment = try #require(card.assessment)
        let until = try #require(assessment.validUntil)
        let aged = card.applyingDeadlines(at: until, tolerance: 300)
        #expect(aged.assessment?.state == "unknown" && aged.assessment?.availability == "unknown")
        #expect(aged.assessment?.evidence.allSatisfy { $0.health == .unknown && $0.freshness == "stale" && $0.worker == "unknown" } == true)
        // Identities and hints stay; the conclusion goes.
        #expect(aged.assessment?.evidence.map(\.check) == assessment.evidence.map(\.check))
        #expect(SectionBuilder.scope(aged.assessment)?.conclusion.isEmpty == true)
        // A deadline far in the future is clock skew, not validity.
        var skewed = card
        skewed.assessment?.validUntil = now.addingTimeInterval(3600)
        #expect(skewed.applyingDeadlines(at: now, tolerance: 300).assessment?.state == "unknown")
        #expect(card.applyingDeadlines(at: now, tolerance: 300).assessment == assessment)
    }

    @Test func aLocalFailureSaysTheAppFails() throws {
        try L10n.with("en") {
            let json = #"{"state":"local_fail","availability":"down","path_reachability":"up","worker_online":"up","evidence":[],"hints":[],"valid_until":null}"#
            let a = try JSONDecoder().decode(ServiceCard.Assessment.self, from: Data(json.utf8))
            let scope = try #require(SectionBuilder.scope(a))
            #expect(scope.conclusion == "Its local health check fails" && scope.mark == .down)
            #expect(scope.detail == "app down · path up · workers up")
            // An unknown hint code is never shown as text.
            let other = try JSONDecoder().decode(ServiceCard.Assessment.self, from: Data(#"{"state":"up","hints":["future_hint"]}"#.utf8))
            #expect(SectionBuilder.scope(other) == nil)
        }
    }
}
