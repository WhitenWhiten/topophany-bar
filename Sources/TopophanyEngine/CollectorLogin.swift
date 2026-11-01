import Foundation
import TopophanyKit

/// The UI owns the token only for this operation. topo verifies the collector
/// before saving its own private credential file. Neither arguments nor output
/// carry the token, and closing the form cancels the bounded child process.
public struct CollectorLoginClient: Sendable {
    public typealias Execute = @Sendable ([String], Data) async throws -> SourcesClient.Output
    private let execute: Execute
    public init(execute: @escaping Execute) { self.execute = execute }
    public init(path: String) {
        execute = { arguments, input in
            try await BoundedCommand.run(path: path, arguments: arguments, input: input, timeout: 30)
        }
    }
    public func login(server: String, project: String, profile: String, token: String,
                      caFile: String = "", allowInsecure: Bool = false, credentials: String? = nil) async throws {
        guard (32...512).contains(token.utf8.count), token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              !server.isEmpty, !project.isEmpty, !profile.isEmpty else { throw SourceProblem(code: "invalid_request") }
        var arguments = ["login", "--server", server, "--project", project, "--profile", profile, "--token-stdin"]
        if !caFile.isEmpty { arguments += ["--ca-file", caFile] }
        if allowInsecure { arguments += ["--allow-insecure"] }
        if let credentials { arguments += ["--credentials", credentials] }
        let output = try await execute(arguments, Data((token + "\n").utf8))
        try Task.checkCancellation()
        guard output.status == 0 else { throw SourceProblem(code: "login_failed") }
    }
}
