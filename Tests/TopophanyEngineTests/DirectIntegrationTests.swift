import Foundation
import Testing
import TopophanyKit
@testable import TopophanyEngine

/// Opt in only to the Go harness's literal-loopback Hub. Never reads the user's direct root.
struct DirectIntegrationTests {
    @Test func realCommandsAndStream() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let binary = env["TOPOPHANY_DIRECT_BINARY"], let readyPath = env["TOPOPHANY_DIRECT_READY"] else { return }
        struct Ready: Decodable { var url: String; var identity: String; var password: String; var token: String; var systems: [String] }
        let ready = try JSONDecoder().decode(Ready.self, from: Data(contentsOf: URL(filePath: readyPath)))
        #expect(URL(string: ready.url)?.host() == "127.0.0.1")
        guard URL(string: ready.url)?.host() == "127.0.0.1" else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: "bar-direct-integration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let caps = try ProcessEngine.check(binary).get()
        #expect(caps.supports(source: "direct"))
        let client = SourcesClient(path: binary, directRoot: root.path)
        let empty = try await client.call(.list, as: DirectProfiles.self)
        #expect(empty.profiles.isEmpty)
        let source = DirectSource(name: "Synthetic Swift source", url: ready.url)
        let auth = SourceAuth.password(identity: ready.identity, password: ready.password)
        let inspection = try await client.call(.inspect, .init(profile: "desktop", source: source, auth: auth), as: DirectInspection.self)
        #expect(inspection.systems.count == ready.systems.count)
        let ids = Array(ready.systems.prefix(2))
        var saved = try await client.call(.save, .init(profile: "desktop", baseRevision: "", source: source, auth: auth, selectedObjects: ids), as: DirectSaved.self)
        #expect(Set(saved.nodes.map(\.id)) == Set(ids.map { source.id + "." + $0 }))
        let listed = try await client.call(.list, as: DirectProfiles.self)
        #expect(listed.profiles.first?.datasetID == saved.datasetID)
        let tokenInspection = try await client.call(.inspect, .init(profile: "desktop", source: source, auth: .token(ready.token)), as: DirectInspection.self)
        #expect(tokenInspection.systems.map(\.id) == inspection.systems.map(\.id))
        let renewed = try await client.call(.save, .init(profile: "desktop", baseRevision: saved.profileRevision, source: source, auth: .saved, selectedObjects: ids), as: DirectSaved.self)
        #expect(renewed.datasetID == saved.datasetID)
        #expect(renewed.profileRevision != saved.profileRevision)
        saved = renewed
        var settings = Settings(); settings.topo.source = "direct"; settings.topo.profile = "desktop"
        settings.topo.profileRevision = saved.profileRevision
        settings.sections.servers = true; settings.sections.serverNodes = saved.nodes.map(\.id)
        var config = ProcessEngine.Configuration(topoPath: binary, shellPath: { "" }); config.directRoot = root.path
        let engine = ProcessEngine(configuration: config)
        let rec = Recorder(engine.start(TemplateCompiler().request(for: settings, revision: 1)))
        let readyFrame = await rec.wait(timeout: 15) { events in
            frames(events).contains { f in f.rows.contains { if case .sources(let s) = $0.value { s.state == "ready" } else { false } } }
        }
        #expect(readyFrame)
        if let frame = rec.frames.last(where: { $0.rows.contains { if case .sources(let s) = $0.value { s.state == "ready" } else { false } } }) {
            #expect(frame.datasetID == saved.datasetID && frame.profileRevision == saved.profileRevision)
            let cards = frame.rows.compactMap { if case .serverCard(let c) = $0.value { c } else { nil } }
            #expect(cards.count == ids.count)
            #expect(cards.allSatisfy { $0.origin?.sourceID == source.id && $0.resources.first?.cpu?.percent != nil })
        }
        var update = TemplateCompiler().request(for: settings, revision: 2)
        update.interval = "1s"; update.template.title = "Synthetic projection only"
        try await engine.update(update)
        #expect(await rec.wait { frames($0).contains { $0.requestID == "settings-2" && $0.lifecycle == .running } })
        update.requestID = "rejected"; update.profileRevision = "stale"
        try await engine.update(update)
        #expect(await rec.wait { frames($0).contains { $0.requestID == "rejected" && $0.error?.code == "profile_conflict" } })
        update.requestID = "retry"; update.profileRevision = saved.profileRevision; update.retryNonce = "synthetic-retry"
        try await engine.update(update)
        #expect(await rec.wait { frames($0).contains { $0.requestID == "retry" && $0.lifecycle == .running } })
        #expect(rec.statuses.filter { if case .running = $0 { true } else { false } }.count == 1)
        await engine.stop(); await rec.finished()
        let removed = try await client.call(.remove, .init(profile: "desktop", baseRevision: saved.profileRevision, sourceID: source.id), as: DirectRemoved.self)
        #expect(removed.sourceID == source.id)
        let final = try await client.call(.list, as: DirectProfiles.self)
        #expect(final.profiles.first?.sources.isEmpty == true)
    }
}
