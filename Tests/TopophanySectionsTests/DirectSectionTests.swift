import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

struct DirectSectionTests {
    @Test func statesPreserveBackendSemantics() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/DirectDevelopment")
        let now = Timestamp.parse("2026-10-21T12:00:00Z")!
        for name in ["loading", "ready", "partial", "no_data", "auth_required", "forbidden", "retrying", "unknown"] {
            let frame = try #require(FrameDecoder.frame(from: Data(contentsOf: root.appending(path: name + ".json"))))
            var policy = ReaderPolicy(); policy.receive(frame, at: now)
            var settings = Settings(); settings.topo.source = "direct"; settings.sections.servers = true
            settings.sections.serverNodes = [frame.rows.last!.select!.node!]
            let panel = SectionBuilder.panel(.init(reading: policy.evaluate(at: now), engine: .running, settings: settings))
            #expect(panel.status.verdictState == nil)
            #expect(panel.status.sources != nil)
            #expect(!panel.status.title.contains("All clear"))
            #expect(panel.seen == nil && panel.map == nil && panel.services.isEmpty && panel.zones == nil)
            #expect(panel.status.count == (name == "ready" || name == "partial" ? nil : 1))
            if name == "ready" {
                #expect(panel.servers.first?.cpu.percent == 27.5)
                #expect(panel.servers.first?.origin?.badge == "Beszel")
                #expect(panel.servers.first?.provider == "")
            }
            let expired = SectionBuilder.status(policy.evaluate(at: now.addingTimeInterval(181)), engine: .running)
            #expect(expired.isBlind && expired.mark == .offline && expired.count == nil)
        }
    }
}
