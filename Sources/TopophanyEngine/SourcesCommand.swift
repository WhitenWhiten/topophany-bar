import Foundation
import Synchronization
import TopophanyKit

/// Authentication is deliberately Encodable only, never part of Settings or a handoff.
public enum SourceAuth: Sendable, Encodable {
    case password(identity: String, password: String)
    case token(String)
    case saved
    enum CodingKeys: String, CodingKey { case mode, identity, password, token }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .password(let identity, let password):
            try c.encode("password", forKey: .mode); try c.encode(identity, forKey: .identity); try c.encode(password, forKey: .password)
        case .token(let token): try c.encode("token", forKey: .mode); try c.encode(token, forKey: .token)
        case .saved: try c.encode("saved", forKey: .mode)
        }
    }
}
public struct SourceCommandRequest: Sendable, Encodable {
    public var schema = 1
    public var requestID = UUID().uuidString
    public var profile: String
    public var baseRevision: String?
    public var source: DirectSource?
    public var auth: SourceAuth?
    public var selectedObjects: [String]?
    public var sourceID: String?
    enum CodingKeys: String, CodingKey {
        case schema, requestID = "request_id", profile, baseRevision = "base_revision", source, auth
        case selectedObjects = "selected_objects", sourceID = "source_id"
    }
    public init(profile: String, baseRevision: String? = nil, source: DirectSource? = nil, auth: SourceAuth? = nil,
                selectedObjects: [String]? = nil, sourceID: String? = nil) {
        self.profile = profile; self.baseRevision = baseRevision; self.source = source; self.auth = auth
        self.selectedObjects = selectedObjects; self.sourceID = sourceID
    }
}

public struct SourcesClient: Sendable {
    public enum Command: String, Sendable { case list, inspect, save, remove }
    public struct Output: Sendable {
        public var status: Int32
        public var stdout: Data
        public init(status: Int32, stdout: Data) { self.status = status; self.stdout = stdout }
    }
    public static func cancelAll() { BoundedCommand.cancelAll() }
    public typealias Execute = @Sendable (Command, Data?) async throws -> Output
    private let execute: Execute
    public init(execute: @escaping Execute) { self.execute = execute }
    public init(path: String, directRoot: String? = nil, timeout: TimeInterval = 45) {
        execute = { command, input in
            var args = ["sources", command.rawValue, command == .list ? "--json" : "--json-stdin"]
            if let directRoot { args += ["--direct-root", directRoot] }
            return try await BoundedCommand.run(path: path, arguments: args, input: input, timeout: timeout)
        }
    }
    public func call<T: Decodable & Sendable>(_ command: Command, _ request: SourceCommandRequest? = nil, as type: T.Type) async throws -> T {
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

/// Bounded multiplexed IO. No shell, inherited stdin, stderr logging, or global environment changes.
enum BoundedCommand {
    private final class Cancellation: Sendable {
        let value = Mutex(false)
    }
    private static let running = Mutex<[UUID: Cancellation]>([:])
    static func cancelAll() {
        running.withLock { commands in for flag in commands.values { flag.value.withLock { $0 = true } } }
    }
    static func run(path: String, arguments: [String], input: Data?, timeout: TimeInterval) async throws -> SourcesClient.Output {
        let cancellation = Cancellation()
        let id = UUID()
        running.withLock { $0[id] = cancellation }
        defer { running.withLock { $0[id] = nil } }
        return try await withTaskCancellationHandler {
            try await Task.detached { try runSync(path: path, arguments: arguments, input: input ?? Data(), timeout: timeout, cancellation: cancellation) }.value
        } onCancel: { cancellation.value.withLock { $0 = true } }
    }
    private static func runSync(path: String, arguments: [String], input: Data, timeout: TimeInterval,
                                cancellation: Cancellation) throws -> SourcesClient.Output {
        let p = Process()
        p.executableURL = URL(filePath: path); p.arguments = arguments
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try p.run() } catch { throw SourceProblem(code: "launch_failed") }
        let writer = stdin.fileHandleForWriting
        let readers = [stdout.fileHandleForReading, stderr.fileHandleForReading]
        for h in [writer] + readers { _ = fcntl(h.fileDescriptor, F_SETFL, O_NONBLOCK) }
        defer {
            for h in [writer] + readers { try? h.close() }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
        }
        let began = ProcessInfo.processInfo.systemUptime
        var exitedAt: TimeInterval?
        var sent = 0, output = Data(), bytes = [0, 0], closed = [false, false], inputClosed = false
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if cancellation.value.withLock({ $0 }) { throw CancellationError() }
            if now - began >= timeout { throw SourceProblem(code: "command_timeout", retryable: true) }
            if !p.isRunning, exitedAt == nil { exitedAt = now }
            if sent == input.count, !inputClosed { try? writer.close(); inputClosed = true }
            var fds = readers.enumerated().map { pollfd(fd: closed[$0.offset] ? -1 : $0.element.fileDescriptor, events: Int16(POLLIN), revents: 0) }
            fds.append(pollfd(fd: inputClosed ? -1 : writer.fileDescriptor, events: Int16(POLLOUT), revents: 0))
            _ = poll(&fds, 3, 50)
            if !inputClosed, fds[2].revents & Int16(POLLOUT) != 0 {
                let n = input.withUnsafeBytes { write(writer.fileDescriptor, $0.baseAddress!.advanced(by: sent), min(16 * 1024, input.count - sent)) }
                if n > 0 { sent += n } else if errno != EAGAIN && errno != EINTR { try? writer.close(); inputClosed = true }
            }
            for i in 0..<2 where !closed[i] && fds[i].revents != 0 {
                let n = buffer.withUnsafeMutableBytes { read(readers[i].fileDescriptor, $0.baseAddress, $0.count) }
                if n > 0 {
                    bytes[i] += n
                    guard bytes[i] <= (i == 0 ? 1 << 20 : 64 * 1024) else { throw SourceProblem(code: "output_limit") }
                    if i == 0 { output.append(contentsOf: buffer.prefix(n)) }
                } else if n == 0 { closed[i] = true }
            }
            if let exitedAt, closed.allSatisfy({ $0 }) || now - exitedAt > 0.5 { break }
        }
        return SourcesClient.Output(status: p.terminationStatus, stdout: output)
    }
}
