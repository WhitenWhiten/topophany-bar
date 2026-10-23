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

extension DirectIntegrationTests {
    /// Opt in with `Tests/Fixtures/DirectDevelopment/fake-komari.py`'s ready file
    /// and a topo whose capabilities offer Komari. Drives the editor as the sheet does.
    @MainActor @Test func realKomariEditorAndStream() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let binary = env["TOPOPHANY_DIRECT_BINARY"], let readyPath = env["TOPOPHANY_KOMARI_READY"] else { return }
        struct Ready: Decodable {
            struct Node: Decodable { var id: String; var name: String; var `public`: Bool }
            var url: String; var key: String; var nodes: [Node]
        }
        let ready = try JSONDecoder().decode(Ready.self, from: Data(contentsOf: URL(filePath: readyPath)))
        #expect(URL(string: ready.url)?.host() == "127.0.0.1")
        guard URL(string: ready.url)?.host() == "127.0.0.1" else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: "bar-komari-integration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let caps = try ProcessEngine.check(binary).get()
        #expect(caps.direct?.known == ["beszel", "komari"])
        let client = SourcesClient(path: binary, directRoot: root.path)
        let editor = SourceEditor(client: client, profile: "desktop", revision: "", adapters: caps.direct?.known ?? [])
        func settle() async { for _ in 0..<400 where editor.busy { try? await Task.sleep(for: .milliseconds(25)) } }
        editor.choose(adapter: "komari")
        #expect(editor.source.intervalSeconds == 30 && editor.authentication == .token)
        editor.source.name = "Synthetic Komari"; editor.source.url = ready.url
        // Public servers only: no key, and the hidden node isn't listed.
        editor.authentication = .anonymous; editor.changed(); editor.inspect(); await settle()
        #expect(Set(editor.inspection?.systems.map(\.id) ?? []) == Set(ready.nodes.filter(\.public).map(\.id)))
        editor.authentication = .token; editor.token = "wrong-synthetic-key"; editor.changed(); editor.inspect(); await settle()
        #expect(editor.problem == "auth_required" && editor.inspection == nil)
        editor.token = ready.key; editor.changed(); editor.inspect(); await settle()
        #expect(editor.inspection?.systems.count == ready.nodes.count)
        editor.selected = Set(ready.nodes.map(\.id))
        nonisolated(unsafe) var saved: DirectSaved?
        editor.onSaved = { saved = $0 }
        editor.save(); await settle()
        let result = try #require(saved)
        #expect(editor.token.isEmpty)
        #expect(Set(result.nodes.map(\.objectID)) == Set(ready.nodes.map(\.id)))
        let entry = try #require(try await client.call(.list, as: DirectProfiles.self).profiles.first?.sources.first)
        #expect(entry.source.adapter == "komari" && entry.authMode == "token")
        // Editing keeps the saved key, and the adapter with it.
        let again = SourceEditor(client: client, profile: "desktop", revision: result.profileRevision, entry: entry, adapters: caps.direct?.known ?? [])
        #expect(again.adapters == ["komari"] && again.methods == [.saved, .token, .anonymous])
        again.inspect()
        for _ in 0..<400 where again.busy { try? await Task.sleep(for: .milliseconds(25)) }
        #expect(again.inspection?.systems.count == ready.nodes.count)
        again.close()
        var settings = Settings(); settings.topo.source = "direct"; settings.topo.profile = "desktop"
        settings.topo.profileRevision = result.profileRevision
        settings.sections.servers = true; settings.sections.serverNodes = result.nodes.map(\.id)
        var config = ProcessEngine.Configuration(topoPath: binary, shellPath: { "" }); config.directRoot = root.path
        let engine = ProcessEngine(configuration: config)
        let rec = Recorder(engine.start(TemplateCompiler().request(for: settings, revision: 1)))
        let isReady: @Sendable (Frame) -> Bool = { f in f.rows.contains { if case .sources(let s) = $0.value { s.state == "ready" } else { false } } }
        #expect(await rec.wait(timeout: 15) { frames($0).contains(where: isReady) })
        if let frame = rec.frames.last(where: isReady) {
            #expect(frame.datasetID == result.datasetID)
            let cards = frame.rows.compactMap { if case .serverCard(let c) = $0.value { c } else { nil } }
            #expect(cards.count == ready.nodes.count)
            #expect(cards.allSatisfy { $0.origin?.adapter == "komari" && $0.resources.first?.disk?.percent != nil })
            #expect(cards.first { $0.origin?.objectID == ready.nodes[0].id }?.resources.first?.cpu?.percent == 12.5)
        }
        await engine.stop(); await rec.finished()
        let removed = try await client.call(.remove, .init(profile: "desktop", baseRevision: result.profileRevision, sourceID: result.sourceID), as: DirectRemoved.self)
        #expect(removed.sourceID == result.sourceID)
    }
}
