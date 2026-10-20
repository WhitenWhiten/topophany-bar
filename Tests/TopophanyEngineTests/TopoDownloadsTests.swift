import CryptoKit
import Foundation
import Testing
@testable import TopophanyEngine
@testable import TopophanyKit

/// Serves fixed bodies, as GitHub would.
struct FakeFetcher: TopoFetcher {
    var bodies: [URL: Data]

    func data(from url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Data {
        guard let d = bodies[url] else { throw TopoFetchProblem.status(404) }
        progress(1)
        return d
    }
}

/// A release archive as topo's are made: a folder holding `topo` and its
/// license.
func archive(_ script: String = FakeTopo.script, version: String = "9.9.9", arch: String = "arm64") throws -> Data {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "archive-" + UUID().uuidString)
    let folder = root.appending(path: "topophany_\(version)_darwin_\(arch)")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try script.write(to: folder.appending(path: "topo"), atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "topo").path)
    try "MIT License".write(to: folder.appending(path: "LICENSE"), atomically: true, encoding: .utf8)
    let out = root.appending(path: "a.tar.gz")
    let r = Subprocess.run("/usr/bin/tar", ["-czf", out.path, "-C", root.path, folder.lastPathComponent], timeout: 30)
    #expect(r?.status == 0)
    return try Data(contentsOf: out)
}

func sha256(_ d: Data) -> String { TopoDownloads.hex(SHA256.hash(data: d)) }

func release(_ data: Data, version: String = "9.9.9", sha: String? = nil) -> (TopoRelease, FakeFetcher) {
    let url = URL(string: "https://example.invalid/topophany_\(version)_darwin_arm64.tar.gz")!
    let r = TopoRelease(version: version, assets: [.init(name: "topophany_\(version)_darwin_arm64.tar.gz", url: url, sha256: sha ?? sha256(data))])
    return (r, FakeFetcher(bodies: [url: data]))
}

func downloadsDirectory() -> TopoDownloads {
    TopoDownloads(directory: FileManager.default.temporaryDirectory.appending(path: "downloads-" + UUID().uuidString))
}

@Suite struct TopoReleaseTests {
    @Test func decodesGitHubsLatest() throws {
        let json = #"""
        {"tag_name":"v1.4.0","prerelease":false,"assets":[
          {"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/x/y/releases/download/v1.4.0/SHA256SUMS.txt","digest":"sha256:00"},
          {"name":"topophany_1.4.0_darwin_arm64.tar.gz","browser_download_url":"https://github.com/x/y/releases/download/v1.4.0/a.tar.gz","digest":"sha256:73CA31A74C8AFBFB6A35B4A562298F21C735F78C3AA6E6E015BD53369529AAB8"},
          {"name":"topophany_1.4.0_darwin_amd64.tar.gz","browser_download_url":"https://github.com/x/y/releases/download/v1.4.0/b.tar.gz"},
          {"name":"topophany_1.4.0_linux_arm64.tar.gz","browser_download_url":"https://github.com/x/y/releases/download/v1.4.0/c.tar.gz"}]}
        """#
        let r = try TopoRelease.decode(api: Data(json.utf8))
        #expect(r.version == "1.4.0")
        #expect(r.asset(arch: "arm64")?.sha256 == "73ca31a74c8afbfb6a35b4a562298f21c735f78c3aa6e6e015bd53369529aab8")
        #expect(r.asset(arch: "amd64")?.sha256 == nil)
        #expect(r.asset(arch: "riscv64") == nil)
        #expect(throws: TopoFetchProblem.unreadableRelease) { try TopoRelease.decode(api: Data("{}".utf8)) }
    }

    /// A release whose API gives no digest falls back to its SHA256SUMS.txt.
    @Test func latestFillsHashesFromTheSums() async throws {
        let api = URL(string: "https://api.github.com/repos/WhitenWhiten/topophany/releases/latest")!
        let sums = URL(string: "https://example.invalid/SHA256SUMS.txt")!
        let json = #"{"tag_name":"v2.0.0","assets":[{"name":"SHA256SUMS.txt","browser_download_url":"https://example.invalid/SHA256SUMS.txt"},{"name":"topophany_2.0.0_darwin_arm64.tar.gz","browser_download_url":"https://example.invalid/a.tar.gz"}]}"#
        let hash = String(repeating: "ab", count: 32)
        let fetcher = FakeFetcher(bodies: [api: Data(json.utf8), sums: Data("\(hash)  topophany_2.0.0_darwin_arm64.tar.gz\n\(hash) *other.zip\n".utf8)])
        let r = try await TopoRelease.latest(fetcher: fetcher)
        #expect(r.version == "2.0.0")
        #expect(r.asset(arch: "arm64")?.sha256 == hash)
    }

    @Test func parsesSums() {
        let a = String(repeating: "0", count: 64), b = String(repeating: "F", count: 64)
        let t = TopoRelease.parse(sums: Data("\(a)  one.tar.gz\n\(b) *two.zip\nnot a line\n".utf8))
        #expect(t == ["one.tar.gz": a, "two.zip": b.lowercased()])
    }

    /// The tested release names its own version and has an archive, with a
    /// whole hash, for both kinds of Mac.
    @Test func testedRelease() {
        let t = TopoRelease.tested
        for arch in ["arm64", "amd64"] {
            let a = t.asset(arch: arch)
            #expect(a?.name == "topophany_\(t.version)_darwin_\(arch).tar.gz")
            #expect(a?.url.absoluteString.contains("/releases/download/v\(t.version)/") == true)
            #expect(a?.sha256?.count == 64)
        }
        #expect(["arm64", "amd64"].contains(TopoRelease.machine))
    }

    @Test func versionsOrder() {
        #expect(TopoDownloads.newer("1.10.0", than: "1.9.2"))
        #expect(TopoDownloads.newer("2.0.0", than: "1.30.4"))
        #expect(!TopoDownloads.newer("1.3.0", than: "1.3.0"))
    }

    /// Opt-in, as it reaches GitHub: the tested release's hashes are the
    /// ones GitHub reports, and the latest offers this Mac an archive with
    /// one. `TOPO_RELEASE_LIVE=1 swift test --filter TopoReleaseTests`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOPO_RELEASE_LIVE"] == "1"))
    func liveRelease() async throws {
        let tag = URL(string: "https://api.github.com/repos/\(TopoRelease.repository)/releases/tags/v\(TopoRelease.tested.version)")!
        let tested = try TopoRelease.decode(api: try await URLSessionFetcher().data(from: tag, progress: { _ in }))
        for a in TopoRelease.tested.assets {
            #expect(tested.assets.first { $0.name == a.name }?.sha256 == a.sha256)
        }
        let latest = try await TopoRelease.latest()
        #expect(latest.asset()?.sha256 != nil)
    }
}

@Suite(.serialized) struct TopoDownloadsTests {
    @Test func installsListsFindsAndDeletes() async throws {
        let d = downloadsDirectory()
        let data = try archive()
        let (r, fetcher) = release(data)
        let got = try await d.install(r, arch: "arm64", fetcher: fetcher)
        #expect(got.version == "9.9.9")
        #expect(got.path == d.directory.appending(path: "9.9.9/topo").path)
        #expect(FileManager.default.fileExists(atPath: d.directory.appending(path: "9.9.9/LICENSE").path))
        #expect(d.installed() == [got])
        // Nothing half-made is left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.directory.path) == ["9.9.9"])

        // Found last, after every place searched.
        let found = TopoLocator(setting: "", shellPath: { "" }, downloads: d).locate()
        if !TopoLocator.fallbacks.contains(where: { FileManager.default.isExecutableFile(atPath: $0 + "/topo") }) {
            #expect(try found.get() == .init(path: got.path, origin: "downloaded"))
        }

        // Again: the same version is replaced, not doubled.
        _ = try await d.install(r, arch: "arm64", fetcher: fetcher)
        #expect(d.installed().count == 1)

        try d.delete(got)
        #expect(d.installed().isEmpty)
    }

    @Test func refusesAWrongHash() async throws {
        let d = downloadsDirectory()
        let (r, fetcher) = release(try archive(), sha: String(repeating: "0", count: 64))
        await #expect(throws: TopoFetchProblem.checksumMismatch(version: "9.9.9")) { try await d.install(r, arch: "arm64", fetcher: fetcher) }
        #expect(d.installed().isEmpty)
    }

    @Test func refusesATopoWithoutTheStream() async throws {
        let d = downloadsDirectory()
        let (r, fetcher) = release(try archive(FakeTopo.old))
        await #expect(throws: TopoFetchProblem.self) { try await d.install(r, arch: "arm64", fetcher: fetcher) }
        do {
            _ = try await d.install(r, arch: "arm64", fetcher: fetcher)
        } catch let p as TopoFetchProblem {
            guard case .unusable("9.9.9", .upgradeNeeded) = p else { Issue.record("\(p)"); return }
        }
        #expect(d.installed().isEmpty)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: d.directory.path)) ?? [] == [])
    }

    @Test func saysWhatsMissing() async throws {
        let d = downloadsDirectory()
        let data = try archive()
        var (r, fetcher) = release(data)
        await #expect(throws: TopoFetchProblem.noArchive(version: "9.9.9")) { try await d.install(r, arch: "riscv64", fetcher: fetcher) }
        r.assets[0].sha256 = nil
        await #expect(throws: TopoFetchProblem.noChecksum(version: "9.9.9")) { try await d.install(r, arch: "arm64", fetcher: fetcher) }
        fetcher.bodies = [:]
        r.assets[0].sha256 = sha256(data)
        await #expect(throws: TopoFetchProblem.status(404)) { try await d.install(r, arch: "arm64", fetcher: fetcher) }
        let (bad, badFetcher) = release(Data("not an archive".utf8))
        await #expect(throws: TopoFetchProblem.unpack(version: "9.9.9")) { try await d.install(bad, arch: "arm64", fetcher: badFetcher) }
    }

    /// Each topo once, however it's linked, in search order, with what the
    /// engine's check says of it.
    @Test func listsCandidates() async throws {
        let fm = FileManager.default
        let good = try FakeTopo.install()
        let old = try FakeTopo.install(FakeTopo.old)
        let linkDir = fm.temporaryDirectory.appending(path: "link-" + UUID().uuidString)
        try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: linkDir.appending(path: "topo").path, withDestinationPath: good)
        let d = downloadsDirectory()
        let (r, fetcher) = release(try archive())
        let got = try await d.install(r, arch: "arm64", fetcher: fetcher)

        let dirs = [good, old].map { ($0 as NSString).deletingLastPathComponent } + [linkDir.path]
        let locator = TopoLocator(setting: got.path, shellPath: { dirs.joined(separator: ":") }, downloads: d)
        let c = locator.candidates().filter { !$0.path.hasPrefix("/opt/homebrew") && !$0.path.hasPrefix("/usr/local") }
        #expect(c.map(\.path) == [good, old, got.path])
        #expect(c.map(\.origin) == [.path, .path, .downloaded])
        #expect(c[0].version == "9.9.9-fake" && c[0].isUsable)
        #expect(c[1].problem == .upgradeNeeded(path: old) && !c[1].isUsable)
        #expect(c[2].version == "9.9.9-fake")
    }
}
