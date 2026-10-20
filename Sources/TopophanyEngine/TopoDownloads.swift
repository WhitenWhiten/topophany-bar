import CryptoKit
import Foundation
import TopophanyKit

/// The copies of `topo` the app downloaded, one folder per version, beside
/// its settings: `topo/1.3.0/topo`. The user can delete any of them.
public struct TopoDownloads: Sendable, Hashable {
    public struct Installed: Sendable, Hashable, Identifiable {
        public var version: String
        public var path: String
        public var id: String { path }

        public init(version: String, path: String) {
            self.version = version
            self.path = path
        }
    }

    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Beside the settings file at `settings`.
    public init(besideSettings settings: URL) {
        directory = settings.deletingLastPathComponent().appending(path: "topo", directoryHint: .isDirectory)
    }

    /// Each downloaded copy, newest first.
    public func installed() -> [Installed] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
            .compactMap { name -> Installed? in
                let path = directory.appending(path: name).appending(path: "topo").path
                return fm.isExecutableFile(atPath: path) ? Installed(version: name, path: path) : nil
            }
            .sorted { Self.newer($0.version, than: $1.version) }
    }

    /// Whether `path` is one of these copies.
    public func contains(_ path: String) -> Bool {
        installed().contains { $0.path == path }
    }

    public func delete(_ installed: Installed) throws {
        try FileManager.default.removeItem(at: URL(filePath: installed.path).deletingLastPathComponent())
    }

    /// Downloads this Mac's archive of `release`, checks its SHA-256,
    /// unpacks `topo` and checks that it speaks protocol 1 before keeping it.
    /// A copy of the same version is replaced. Throws `TopoFetchProblem`.
    public func install(_ release: TopoRelease, arch: String = TopoRelease.machine,
                        fetcher: any TopoFetcher = URLSessionFetcher(),
                        progress: @escaping @Sendable (Double?) -> Void = { _ in }) async throws -> Installed {
        let version = release.version
        guard let asset = release.asset(arch: arch) else { throw TopoFetchProblem.noArchive(version: version) }
        guard let expected = asset.sha256 else { throw TopoFetchProblem.noChecksum(version: version) }
        let archive = try await fetcher.data(from: asset.url, progress: progress)
        guard Self.hex(SHA256.hash(data: archive)) == expected.lowercased() else {
            throw TopoFetchProblem.checksumMismatch(version: version)
        }

        let fm = FileManager.default
        let work = directory.appending(path: ".partial-" + UUID().uuidString, directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }
        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        let file = work.appending(path: asset.name)
        do {
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            try archive.write(to: file)
        } catch {
            throw TopoFetchProblem.storage(error.localizedDescription)
        }
        guard let out = Subprocess.run("/usr/bin/tar", ["-xzf", file.path, "-C", unpacked.path], timeout: 60), out.status == 0,
              let topo = Self.findTopo(in: unpacked) else {
            throw TopoFetchProblem.unpack(version: version)
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: topo.path)
        if case .failure(let problem) = ProcessEngine.check(topo.path) {
            throw TopoFetchProblem.unusable(version: version, problem)
        }

        let home = directory.appending(path: version, directoryHint: .isDirectory)
        do {
            if fm.fileExists(atPath: home.path) { try fm.removeItem(at: home) }
            try fm.moveItem(at: topo.deletingLastPathComponent(), to: home)
        } catch {
            throw TopoFetchProblem.storage(error.localizedDescription)
        }
        return Installed(version: version, path: home.appending(path: "topo").path)
    }

    /// The archive's `topo`: a regular file, at most a folder down.
    static func findTopo(in dir: URL) -> URL? {
        let fm = FileManager.default
        let top = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in [dir.appending(path: "topo")] + top.map({ $0.appending(path: "topo") }) {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isRegularFile == true, values?.isSymbolicLink != true { return url }
        }
        return nil
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether version `a` is newer than `b`: "1.10.0" after "1.9.2".
    public static func newer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}
