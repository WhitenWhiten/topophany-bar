import Foundation
import Testing
import TopophanyKit
@testable import TopophanyEngine

/// Opt in only, against a synthetic mihomo engine on literal loopback (an
/// OrbStack container in development). Uses a temporary local root: it never
/// reads the user's saved checks or a proxy app's engine.
@MainActor struct LocalIntegrationTests {
    @Test func realCommandsAndStream() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let binary = env["TOPOPHANY_LOCAL_BINARY"], let url = env["TOPOPHANY_LOCAL_ENGINE"], let secret = env["TOPOPHANY_LOCAL_SECRET"] else { return }
        #expect(URL(string: url)?.host() == "127.0.0.1")
        guard URL(string: url)?.host() == "127.0.0.1", URL(string: url)?.port != 9090 else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: "bar-local-integration-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let caps = try ProcessEngine.check(binary).get()
        #expect(caps.supports(source: "local") && caps.local?.readsMihomo == true)
        let client = LocalClient(path: binary, localRoot: root.path)
        let empty = try await client.call(.list, as: LocalChecks.self)
        #expect(empty.checks.isEmpty)

        // The editor's own path: a wrong secret, then the right one with a pasted newline.
        let editor = LocalEditor(client: client, revision: empty.profileRevision, name: "Synthetic engine")
        editor.check.url = url; editor.token = "not-the-secret"
        editor.inspect()
        for _ in 0..<400 where editor.busy { try await Task.sleep(for: .milliseconds(10)) }
        #expect(editor.problem == "authentication_failed")
        editor.token = secret + "\n"; editor.changed()
        editor.inspect()
        for _ in 0..<400 where editor.busy { try await Task.sleep(for: .milliseconds(10)) }
        let inspection = try #require(editor.inspection)
        #expect(inspection.engine.mode == "rule" && inspection.groups.contains { $0.name == "Proxy" })
        editor.check.rootProxy = "Proxy"; editor.check.expectedMode = "rule"
        var saved: LocalChanged?
        editor.onSaved = { saved = $0 }
        editor.save()
        for _ in 0..<400 where saved == nil && editor.problem == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(saved != nil && editor.token.isEmpty)

        // The reader follows it in its own stream.
        let reader = LocalReader(makeClient: { LocalClient(path: $0, localRoot: root.path) }, makeEngine: { path in
            var c = ProcessEngine.Configuration(topoPath: path, shellPath: { "" }); c.localRoot = root.path
            return ProcessEngine(configuration: c)
        })
        reader.attach(path: binary)
        defer { reader.closeNow() }
        var card: ServiceCard.Check?
        for _ in 0..<1500 {
            if let r = reader.evaluate(at: Date()), let row = r.rows.first, case .checkCard(let c) = r.lastValue(of: row), c.check.freshness == "fresh" {
                card = c.check; break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let check = try #require(card)
        #expect(check.kind == "mihomo" && check.health == .up && check.diagnostic?.policy == "matched")
        #expect(reader.pins == [MonitorPin(kind: .check, id: editor.check.id)] && reader.problem == nil)
    }
}
