import Foundation
import Testing
import TopophanyKit
import TopophanyEngine
import TopophanySections
import TopophanyThemes
import TopophanyWidgets

@Suite struct ContinuityTests {
    @Test func failedFrameRoundTripsWithLastSnapshotAndRecovers() throws {
        let line = FixtureEngine.lines(.incidents)[0]
        let f = try #require(FrameDecoder.frame(from: line))
        let at = try #require(f.generatedAt)
        var reader = ReaderPolicy()
        reader.receive(f, line: line, at: at)
        let initial = reader.evaluate(at: at)
        var json = try #require(JSONSerialization.jsonObject(with: line) as? [String: Any])
        json["sequence"] = (f.sequence ?? 0) + 1
        json["generated_at"] = Timestamp.format(at.addingTimeInterval(20))
        json["publisher_expires_at"] = Timestamp.format(at.addingTimeInterval(50))
        json["rows"] = try #require(json["rows"] as? [[String: Any]]).map { row in
            var r = row; r["value"] = NSNull(); r["reason"] = "source_unavailable"; return r
        }
        let failedLine = try JSONSerialization.data(withJSONObject: json)
        reader.receive(try #require(FrameDecoder.frame(from: failedLine)), line: failedLine, at: at.addingTimeInterval(20))
        #expect(reader.evaluate(at: at.addingTimeInterval(20)).row("status")?.value == RowValue.none)
        let handoff = Handoff(policy: reader, theme: ThemeStore.native, settings: settings(), engineRunning: true,
                              at: at.addingTimeInterval(20))
        let restored = try JSONDecoder().decode(Handoff.self, from: JSONEncoder().encode(handoff))
        let panel = restored.panel()
        #expect(panel.status.historicalAt == at)
        #expect(panel.status.counts == SectionBuilder.status(initial, engine: .running).counts)
        #expect(panel.attention?.items.isEmpty == false)
        let node = try #require(f.rows.first { $0.metric == "server.card" }?.select?.node)
        let server = restored.panel(server: node).servers.first { $0.id == node }
        #expect(server?.cpu.percent == SectionBuilder.servers(initial, nodes: [node]).first?.cpu.percent)
        #expect(server?.isWithheld == false)
        #expect(restored.reading().row("status")?.value == RowValue.none)

        var recovered = f
        recovered.sequence = (f.sequence ?? 0) + 2
        recovered.generatedAt = at.addingTimeInterval(25); recovered.publisherExpiresAt = at.addingTimeInterval(55)
        for i in recovered.rows.indices { recovered.rows[i].validUntil = at.addingTimeInterval(40) }
        reader.receive(recovered, at: at.addingTimeInterval(25))
        let current = SectionBuilder.panel(PanelInput(reading: reader.evaluate(at: at.addingTimeInterval(25)), engine: .running, settings: settings()))
        #expect(current.status.historicalAt == nil)
        #expect(!current.status.isBlind)
    }
}
