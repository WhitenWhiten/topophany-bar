import Foundation
import TopophanyKit

/// Finds `topo`: the path setting, then the login shell's `PATH`, then
/// `/opt/homebrew/bin` and `/usr/local/bin`.
public struct TopoLocator: Sendable {
    public struct Found: Sendable, Hashable {
        public var path: String
        /// Where it was found: `setting`, `PATH` or `fallback`.
        public var origin: String
    }

    public static let fallbacks = ["/opt/homebrew/bin", "/usr/local/bin"]

    public var setting: String
    public var shellPath: @Sendable () -> String?

    public init(setting: String, shellPath: @escaping @Sendable () -> String? = { TopoLocator.loginShellPATH() }) {
        self.setting = setting
        self.shellPath = shellPath
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
        return .failure(.notFound(searched: searched))
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
