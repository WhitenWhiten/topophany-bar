import Foundation
import Testing
import TopophanyKit
@testable import TopophanyEngine

struct SourcesCommandTests {
    @Test func envelopeValidation() async throws {
        let client = SourcesClient { _, _ in .init(status: 0, stdout: Data(#"{"schema":1,"request_id":"","ok":true,"data":{"profiles":[]}}"#.utf8)) }
        #expect(try await client.call(.list, as: DirectProfiles.self).profiles.isEmpty)
        for out in [SourcesClient.Output(status: 1, stdout: Data(#"{"schema":1,"request_id":"","ok":true,"data":{"profiles":[]}}"#.utf8)),
                    .init(status: 0, stdout: Data("bad-json".utf8)),
                    .init(status: 0, stdout: Data(#"{"schema":1,"request_id":"wrong","ok":true,"data":{"profiles":[]}}"#.utf8))] {
            let bad = SourcesClient { _, _ in out }
            await #expect(throws: SourceProblem.self) { try await bad.call(.list, as: DirectProfiles.self) }
        }
    }
    @Test func subprocessBoundsAndCancellation() async throws {
        for (script, code) in [("sleep 5", "command_timeout"), ("head -c 1048577 /dev/zero", "output_limit"), ("head -c 65537 /dev/zero >&2", "output_limit")] {
            do {
                _ = try await BoundedCommand.run(path: "/bin/sh", arguments: ["-c", script], input: nil, timeout: 0.2)
                Issue.record("expected failure")
            } catch { #expect((error as? SourceProblem)?.code == code) }
        }
        let task = Task { try await BoundedCommand.run(path: "/bin/sleep", arguments: ["5"], input: nil, timeout: 10) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @MainActor @Test func editorSelectionAndSecretLifetime() async throws {
        let client = SourcesClient { command, data in
            let input = try JSONSerialization.jsonObject(with: data!) as! [String: Any]
            let id = input["request_id"] as! String
            if command == .inspect {
                return .init(status: 0, stdout: Data("{\"schema\":1,\"request_id\":\"\(id)\",\"ok\":true,\"data\":{\"source\":{\"id\":\"bs-a\",\"name\":\"Synthetic\",\"adapter\":\"beszel\",\"url\":\"http://127.0.0.1\"},\"systems\":[{\"id\":\"one\",\"name\":\"same\"},{\"id\":\"two\",\"name\":\"same\"}],\"truncated\":true,\"limits\":{\"max_selected\":20},\"warnings\":[]}}".utf8))
            }
            throw SourceProblem(code: "synthetic")
        }
        let editor = SourceEditor(client: client, profile: "desktop", revision: "")
        let sourceID = editor.source.id
        editor.password = "canary-never-persist"
        editor.inspect(); editor.inspect()
        for _ in 0..<50 where editor.busy { try await Task.sleep(for: .milliseconds(10)) }
        #expect(editor.inspection?.systems.count == 2)
        #expect(editor.inspection?.truncated == true)
        #expect(!editor.canSave)
        editor.selected = ["one"]; #expect(editor.canSave)
        editor.selected = Set((0..<21).map(String.init)); #expect(!editor.canSave)
        editor.changed(); #expect(editor.inspection == nil)
        #expect(editor.source.id == sourceID)
        editor.close(); #expect(editor.password.isEmpty && editor.token.isEmpty)
        let settings = try JSONEncoder().encode(Settings())
        #expect(!String(decoding: settings, as: UTF8.self).contains("canary"))
    }
}

extension SourcesCommandTests {
    @MainActor @Test func conflictReadsBeforeRetryAndLateInspectIsIgnored() async throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/contracts/direct-v1/fixtures")
        let listBytes = try Data(contentsOf: root.appending(path: "sources-list-success.json"))
        let list = try JSONDecoder().decode(SourceEnvelope<DirectProfiles>.self, from: listBytes)
        let inspectionBytes = try Data(contentsOf: root.appending(path: "sources-inspect-success.json"))
        let client = SourcesClient { command, input in
            if command == .list { return .init(status: 0, stdout: listBytes) }
            let request = try JSONSerialization.jsonObject(with: input!) as! [String: Any]
            let requestID = request["request_id"] as! String
            if command == .inspect {
                try await Task.sleep(for: .milliseconds(30))
                // Deliberately deliver a result even after cancellation.
                var object = try JSONSerialization.jsonObject(with: inspectionBytes) as! [String: Any]
                object["request_id"] = requestID
                return .init(status: 0, stdout: try JSONSerialization.data(withJSONObject: object))
            }
            let error: [String: Any] = ["schema": 1, "request_id": requestID, "ok": false,
                                       "error": ["code": "profile_conflict", "message": "Synthetic", "retryable": false]]
            return .init(status: 1, stdout: try JSONSerialization.data(withJSONObject: error))
        }
        let entry = try #require(list.data?.profiles.first?.sources.first)
        let editor = SourceEditor(client: client, profile: "desktop", revision: "old", entry: entry)
        #expect(editor.authentication == .saved)
        editor.inspect()
        for _ in 0..<100 where editor.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(editor.canSave)
        editor.save()
        for _ in 0..<100 where editor.busy { try await Task.sleep(for: .milliseconds(5)) }
        #expect(editor.needsReview && editor.currentProfile?.sources.count == 1)
        #expect(editor.revision == "revision-synthetic-1" && !editor.canSave)
        editor.acknowledgeReview(); #expect(editor.canSave)
        editor.inspect(); editor.changed()
        try await Task.sleep(for: .milliseconds(50))
        #expect(editor.inspection == nil && !editor.busy)
        editor.source.url = "http://127.0.0.1:9999"; editor.inspect()
        #expect(editor.problem == "hub_changed")
        editor.close()
    }
}
