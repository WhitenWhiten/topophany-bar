import Foundation
import TopophanyKit

/// A release of `topo` on GitHub, which the app downloads `topo` from when
/// the user asks: the latest, or the one this app was tested with.
public struct TopoRelease: Sendable, Hashable {
    public struct Asset: Sendable, Hashable {
        public var name: String
        public var url: URL
        /// The archive's SHA-256 in hex, when the release says it.
        public var sha256: String?

        public init(name: String, url: URL, sha256: String?) {
            self.name = name
            self.url = url
            self.sha256 = sha256
        }
    }

    /// "1.3.0"
    public var version: String
    public var assets: [Asset]

    public init(version: String, assets: [Asset]) {
        self.version = version
        self.assets = assets
    }

    public static let repository = "WhitenWhiten/topophany"

    /// The release this app was tested with. Its archives' hashes are fixed
    /// here, so it never depends on what GitHub's API says.
    public static let tested: TopoRelease = {
        let version = TopoBuild.testedVersion
        func asset(_ arch: String, _ sha256: String) -> Asset {
            let name = "topophany_\(version)_darwin_\(arch).tar.gz"
            return Asset(name: name, url: URL(string: "https://github.com/\(repository)/releases/download/v\(version)/\(name)")!,
                         sha256: sha256)
        }
        return TopoRelease(version: version, assets: [
            asset("arm64", "5c2be26ddfb65782b1acb0891db6458ea6c2677b151926d78520cd46ccaf47a6"),
            asset("amd64", "007c7c21013605c0ec4e8cd5fc215b28f1a41209b9f3b1d9e6358893d9b7fb82"),
        ])
    }()

    /// This Mac's archive.
    public func asset(arch: String = TopoRelease.machine) -> Asset? {
        assets.first { $0.name.hasSuffix("_darwin_\(arch).tar.gz") }
    }

    /// `arm64` on Apple silicon, even for an app running under Rosetta;
    /// `amd64` otherwise, as Go names them.
    public static var machine: String {
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 && arm == 1 ? "arm64" : "amd64"
    }

    /// The latest release, as GitHub's API describes it. Each archive's hash
    /// comes from the API, or else from the release's `SHA256SUMS.txt`.
    public static func latest(fetcher: any TopoFetcher = URLSessionFetcher()) async throws -> TopoRelease {
        let api = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var release = try decode(api: try await fetcher.data(from: api, progress: { _ in }))
        if release.assets.contains(where: { $0.sha256 == nil }),
           let sums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }) {
            let table = parse(sums: try await fetcher.data(from: sums.url, progress: { _ in }))
            for i in release.assets.indices where release.assets[i].sha256 == nil {
                release.assets[i].sha256 = table[release.assets[i].name]
            }
        }
        return release
    }

    /// A release from GitHub's API: `tag_name` without its `v`, and each
    /// asset with the `digest` GitHub computed, when it says one.
    static func decode(api data: Data) throws -> TopoRelease {
        struct Release: Decodable {
            struct Asset: Decodable {
                var name: String
                var browser_download_url: URL
                var digest: String?
            }
            var tag_name: String
            var assets: [Asset]
        }
        guard let r = try? JSONDecoder().decode(Release.self, from: data) else {
            throw TopoFetchProblem.unreadableRelease
        }
        let version = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        return TopoRelease(version: version, assets: r.assets.map { a in
            let hex = a.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
            return Asset(name: a.name, url: a.browser_download_url, sha256: hex)
        })
    }

    /// `sha256sum` lines: the hash, then the name, which may be marked
    /// binary with `*`.
    static func parse(sums data: Data) -> [String: String] {
        var table: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, parts[0].count == 64 else { continue }
            var name = parts[1].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            table[name] = parts[0].lowercased()
        }
        return table
    }
}

/// Fetches a URL's body: URLSession, or a stand-in in tests.
public protocol TopoFetcher: Sendable {
    /// `progress` gets the share fetched so far, when the size is known.
    func data(from url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Data
}

public struct URLSessionFetcher: TopoFetcher {
    public init() {}

    public func data(from url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("topophany-bar", forHTTPHeaderField: "User-Agent")
        if url.host() == "api.github.com" { request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw TopoFetchProblem.unreachable(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw TopoFetchProblem.status(http.statusCode) }
        let expected = response.expectedContentLength
        var data = Data()
        if expected > 0 { data.reserveCapacity(Int(expected)) }
        progress(expected > 0 ? 0 : nil)
        var chunk: [UInt8] = []
        chunk.reserveCapacity(1 << 16)
        do {
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count == 1 << 16 {
                    data.append(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                    if expected > 0 { progress(min(1, Double(data.count) / Double(expected))) }
                }
            }
        } catch {
            throw TopoFetchProblem.unreachable(error.localizedDescription)
        }
        data.append(contentsOf: chunk)
        return data
    }
}
