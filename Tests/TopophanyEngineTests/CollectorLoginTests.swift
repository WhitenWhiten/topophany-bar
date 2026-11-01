import Foundation
import Testing
import TopophanyKit
@testable import TopophanyEngine

struct CollectorLoginTests {
    @Test func credentialTravelsOnlyThroughInput() async throws {
        let token = String(repeating: "x", count: 64)
        let client = CollectorLoginClient { arguments, input in
            #expect(!arguments.joined(separator: " ").contains(token))
            #expect(arguments.contains("--token-stdin"))
            #expect(String(data: input, encoding: .utf8) == token + "\n")
            return .init(status: 0, stdout: Data())
        }
        try await client.login(server: "https://example.invalid", project: "home", profile: "default", token: token)
    }
    @Test func failureDoesNotReflectProcessOutput() async {
        let client = CollectorLoginClient { _, _ in .init(status: 1, stdout: Data("private output".utf8)) }
        do {
            try await client.login(server: "https://example.invalid", project: "home", profile: "default", token: String(repeating: "x", count: 64))
            Issue.record("failed login accepted")
        } catch { #expect((error as? SourceProblem)?.code == "login_failed") }
    }
}
