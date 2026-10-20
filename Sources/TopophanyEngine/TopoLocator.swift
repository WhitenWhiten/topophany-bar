import Foundation
import Synchronization
import TopophanyKit

/// Finds `topo`: the path setting, then the login shell's `PATH`, then
/// `/opt/homebrew/bin` and `/usr/local/bin`, then the copies the app
/// downloaded, newest first.
public struct TopoLocator: Sendable {
    public struct Found: Sendable, Hashable {
        public var path: String
        /// Where it was found: `setting`, `PATH`, `fallback` or `downloaded`.
        public var origin: String
    }

    public static let fallbacks = ["/opt/homebrew/bin", "/usr/local/bin"]

    public var setting: String
    public var shellPath: @Sendable () -> String?
    public var downloads: TopoDownloads?

    public init(setting: String, shellPath: @escaping @Sendable () -> String? = { TopoLocator.loginShellPATH() },
                downloads: TopoDownloads? = nil) {
        self.setting = setting
        self.shellPath = shellPath
        self.downloads = downloads
    }

    /// The executable, or every place searched.
    public func locate() -> Result<Found, EngineProblem> {
        var searched: [String] = []
        let fm = FileManager.default
        let setting = (self.setting as NSString).expandingTildeInPath
        if !setting.isEmpty {
            searched.append(setting)
            if fm.isExecutableFile(atPath: setting) { return .success(Found(path: setting, origin: "setting")) }
        }
        let dirs = (shellPath() ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for dir in dirs {
            let p = (dir as NSString).appendingPathComponent("topo")
            searched.append(p)
            if fm.isExecutableFile(atPath: p) { return .success(Found(path: p, origin: "PATH")) }
        }
        for dir in Self.fallbacks where !dirs.contains(dir) {
            let p = (dir as NSString).appendingPathComponent("topo")
            searched.append(p)
            if fm.isExecutableFile(atPath: p) { return .success(Found(path: p, origin: "fallback")) }
        }
        if let first = downloads?.installed().first { return .success(Found(path: first.path, origin: "downloaded")) }
        return .failure(.notFound(searched: searched))
    }

    /// Every `topo` it can see, once each however it's linked, in the order
    /// it searches: the setting's, then `PATH`'s, the fallbacks' and the
    /// downloaded copies. Each is checked as the engine checks it.
    public func candidates() -> [TopoCandidate] {
        let fm = FileManager.default
        var found: [(String, TopoCandidate.Origin)] = []
        let setting = (self.setting as NSString).expandingTildeInPath
        if !setting.isEmpty, fm.isExecutableFile(atPath: setting) { found.append((setting, .setting)) }
        let dirs = (shellPath() ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for dir in dirs {
            let p = (dir as NSString).appendingPathComponent("topo")
            if fm.isExecutableFile(atPath: p) { found.append((p, .path)) }
        }
        for dir in Self.fallbacks where !dirs.contains(dir) {
            let p = (dir as NSString).appendingPathComponent("topo")
            if fm.isExecutableFile(atPath: p) { found.append((p, .fallback)) }
        }
        for d in downloads?.installed() ?? [] { found.append((d.path, .downloaded)) }
        // A downloaded copy is listed as one even when the setting names it.
        let downloaded = Set(found.filter { $0.1 == .downloaded }.map { Self.resolved($0.0) })
        var seen = Set<String>()
        var unique: [(String, TopoCandidate.Origin)] = []
        for (path, origin) in found {
            let real = Self.resolved(path)
            if origin != .downloaded, downloaded.contains(real) { continue }
            if seen.insert(real).inserted { unique.append((path, origin)) }
        }
        var out = unique.map { TopoCandidate(path: $0.0, origin: $0.1) }
        let checks = Mutex<[Int: Result<Capabilities, EngineProblem>]>([:])
        let paths = out.map(\.path)
        DispatchQueue.concurrentPerform(iterations: paths.count) { i in
            let r = ProcessEngine.check(paths[i], timeout: 5)
            checks.withLock { $0[i] = r }
        }
        let results = checks.withLock { $0 }
        for i in out.indices {
            switch results[i] {
            case .success(let caps)?: out[i].version = caps.version
            case .failure(let problem)?:
                out[i].problem = problem
                if case .unsupported(_, let v, _) = problem { out[i].version = v }
            case nil: break
            }
        }
        return out
    }

    static func resolved(_ path: String) -> String {
        URL(filePath: path).resolvingSymlinksInPath().path
    }

    /// `PATH` as the user's login shell sets it, read once per launch of a
    /// short-lived shell. An app started from Finder doesn't inherit it.
    public static func loginShellPATH(timeout: TimeInterval = 5) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let marker = "__topophany_bar_path__"
        let r = Subprocess.run(shell, ["-ilc", "printf '\(marker)%s\(marker)' \"$PATH\""], timeout: timeout)
        guard let out = r?.stdout, let s = String(data: out, encoding: .utf8) else { return nil }
        let parts = s.components(separatedBy: marker)
        return parts.count >= 3 ? parts[parts.count - 2] : nil
    }
}

/// A `topo` on this Mac, and whether the app can run it.
public struct TopoCandidate: Sendable, Hashable, Identifiable {
    public enum Origin: Sendable, Hashable {
        /// Chosen in Settings, outside the places searched.
        case setting
        case path
        case fallback
        case downloaded
    }

    public var path: String
    public var origin: Origin
    /// From its capabilities, when it has `monitor stream`.
    public var version: String?
    /// Why it can't be used; `nil` when it can.
    public var problem: EngineProblem?
    public var id: String { path }
    public var isUsable: Bool { problem == nil }

    public init(path: String, origin: Origin, version: String? = nil, problem: EngineProblem? = nil) {
        self.path = path
        self.origin = origin
        self.version = version
        self.problem = problem
    }
}

/// Runs a short command to completion with a deadline.
enum Subprocess {
    struct Output: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: Data
    }

    static func run(_ path: String, _ args: [String], timeout: TimeInterval) -> Output? {
        let p = Process()
        p.executableURL = URL(filePath: path)
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        let collected = Collector()
        let group = DispatchGroup()
        for (handle, isOut) in [(out.fileHandleForReading, true), (err.fileHandleForReading, false)] {
            group.enter()
            DispatchQueue.global().async {
                let d = handle.readDataToEndOfFile()
                collected.set(d, isOut: isOut)
                group.leave()
            }
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 1)
            return nil
        }
        _ = group.wait(timeout: .now() + 1)
        let (o, e) = collected.get()
        return Output(status: p.terminationStatus, stdout: o, stderr: e)
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()

        func set(_ d: Data, isOut: Bool) {
            lock.withLock { if isOut { out = d } else { err = d } }
        }

        func get() -> (Data, Data) { lock.withLock { (out, err) } }
    }
}
