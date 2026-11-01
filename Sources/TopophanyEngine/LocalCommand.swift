import Foundation
import Observation
import TopophanyKit

/// How a local check's engine takes its secret. Encodable only: it lives in
/// one command's stdin and is never part of Settings or a handoff.
public enum LocalAuth: Sendable, Encodable, Equatable {
    case token(String)
    /// The engine asks for no secret.
    case none
    /// The secret `topo` saved for this check.
    case saved
    enum CodingKeys: String, CodingKey { case mode, token }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .token(let token): try c.encode("token", forKey: .mode); try c.encode(token, forKey: .token)
        case .none: try c.encode("none", forKey: .mode)
        case .saved: try c.encode("saved", forKey: .mode)
        }
    }
}

public struct LocalCommandRequest: Sendable, Encodable {
    public var schema = 1
    public var requestID = UUID().uuidString
    public var baseRevision: String?
    public var check: LocalCheck?
    public var auth: LocalAuth?
    public var checkID: String?
    enum CodingKeys: String, CodingKey { case schema, requestID = "request_id", baseRevision = "base_revision", check, auth, checkID = "check_id" }
    public init(baseRevision: String? = nil, check: LocalCheck? = nil, auth: LocalAuth? = nil, checkID: String? = nil) {
        self.baseRevision = baseRevision; self.check = check; self.auth = auth; self.checkID = checkID
    }
}

/// `topo local list|inspect|save|remove`, bounded like `topo sources`.
public struct LocalClient: Sendable {
    public enum Command: String, Sendable { case list, inspect, save, remove }
    public typealias Execute = @Sendable (Command, Data?) async throws -> SourcesClient.Output
    private let execute: Execute
    public init(execute: @escaping Execute) { self.execute = execute }
    public init(path: String, localRoot: String? = nil, timeout: TimeInterval = 30) {
        execute = { command, input in
            var args = ["local", command.rawValue, command == .list ? "--json" : "--json-stdin"]
            if let localRoot { args += ["--local-root", localRoot] }
            return try await BoundedCommand.run(path: path, arguments: args, input: input, timeout: timeout)
        }
    }
    public func call<T: Decodable & Sendable>(_ command: Command, _ request: LocalCommandRequest? = nil, as type: T.Type) async throws -> T {
        let input = try request.map { try JSONEncoder().encode($0) }
        guard input?.count ?? 0 <= 256 * 1024 else { throw SourceProblem(code: "state_budget") }
        let out = try await execute(command, input)
        try Task.checkCancellation()
        guard out.stdout.count <= 1 << 20,
              let e = try? JSONDecoder().decode(SourceEnvelope<T>.self, from: out.stdout),
              e.schema == 1, e.requestID == (request?.requestID ?? ""),
              [0, 1, 2].contains(out.status), (out.status == 0) == e.ok else { throw SourceProblem(code: "invalid_response") }
        if e.ok, let data = e.data, e.error == nil { return data }
        if !e.ok, e.data == nil, let error = e.error { throw error }
        throw SourceProblem(code: "invalid_response")
    }
}

/// Setting up the proxy engine on this Mac. Owns the typed secret; it is
/// discarded on saving or closing, and a late reply can't replace a newer
/// form.
@MainActor @Observable
public final class LocalEditor: Identifiable {
    public let id = UUID()
    public enum Secret: String, CaseIterable { case saved, token, none }
    public var check: LocalCheck
    public var secret: Secret
    public var token = ""
    public private(set) var inspection: LocalInspection?
    public private(set) var busy = false
    public private(set) var problem: String?
    public private(set) var needsReview = false
    public let isNew: Bool
    @ObservationIgnored private let savedURL: String?
    @ObservationIgnored private var revision: String
    @ObservationIgnored private let client: LocalClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var closed = false
    @ObservationIgnored public var onSaved: ((LocalChanged) -> Void)?

    public init(client: LocalClient, revision: String, entry: LocalChecks.Entry? = nil, name: String = "") {
        self.client = client; self.revision = revision
        isNew = entry == nil
        savedURL = entry?.check.url
        check = entry?.check ?? LocalCheck(name: name)
        secret = entry == nil ? .token : .saved
    }

    /// Ways to give the secret: the saved one is offered only for a check
    /// that has one.
    public var secrets: [Secret] { isNew ? [.token, .none] : [.saved, .token, .none] }
    public var urlIsLocal: Bool { LocalCheck.isLocal(check.url) }
    public var canSave: Bool { !busy && !needsReview && inspection != nil && urlIsLocal && !check.name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var auth: LocalAuth {
        switch secret {
        case .saved: .saved
        // A pasted secret often brings a space or newline with it.
        case .token: .token(token.trimmingCharacters(in: .whitespacesAndNewlines))
        case .none: .none
        }
    }

    /// For edits to the address or secret: a reading of the old form no longer counts.
    public func changed() {
        generation += 1; operation?.cancel(); operation = nil
        inspection = nil; problem = nil; busy = false
    }

    public func close() {
        closed = true; generation += 1; operation?.cancel(); operation = nil; busy = false; token = ""; onSaved = nil
    }

    /// Reads the engine once with this form's address and secret.
    public func inspect() {
        guard !busy, !closed else { return }
        guard urlIsLocal else { problem = "not_local_address"; return }
        if secret == .saved, savedURL != check.url { problem = "saved_auth_mismatch"; return }
        generation += 1
        let g = generation, request = LocalCommandRequest(check: check, auth: auth)
        busy = true; problem = nil; inspection = nil
        operation = Task { [weak self, client] in
            do {
                let result = try await client.call(.inspect, request, as: LocalInspection.self)
                guard let self, !self.closed, self.generation == g else { return }
                self.inspection = result
                // A group the engine no longer has is not followed.
                if !self.check.rootProxy.isEmpty, !result.groups.contains(where: { $0.name == self.check.rootProxy }), !result.truncated {
                    self.check.rootProxy = ""
                }
                self.busy = false
            } catch {
                guard let self, !self.closed, self.generation == g else { return }
                self.problem = (error as? SourceProblem)?.code ?? "command_cancelled"; self.busy = false
            }
        }
    }

    public func save() {
        guard canSave, !closed else { return }
        generation += 1
        let g = generation
        var c = check
        c.name = c.name.trimmingCharacters(in: .whitespaces)
        let request = LocalCommandRequest(baseRevision: revision, check: c, auth: auth)
        busy = true; problem = nil
        operation = Task { [weak self, client] in
            do {
                let saved = try await client.call(.save, request, as: LocalChanged.self)
                guard let self, !self.closed, self.generation == g else { return }
                self.busy = false; self.token = ""; self.onSaved?(saved)
            } catch {
                guard let self, !self.closed, self.generation == g else { return }
                let code = (error as? SourceProblem)?.code ?? "command_cancelled"
                self.problem = code
                // It may have been written anyway: read the revision before any retry.
                if ["profile_conflict", "command_timeout", "command_cancelled", "invalid_response", "output_limit"].contains(code) {
                    self.needsReview = true
                    if let list = try? await client.call(.list, as: LocalChecks.self), !self.closed, self.generation == g {
                        self.revision = list.profileRevision
                    }
                }
                self.busy = false
            }
        }
    }

    public func acknowledgeReview() { needsReview = false }
}
