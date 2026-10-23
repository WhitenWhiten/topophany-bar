import Foundation

/// Which of `topo`'s releases to download: the latest, or the one this app
/// was tested with, for when the latest doesn't work.
public enum TopoBuild: Sendable, Hashable {
    case latest
    case tested

    /// The release this app was tested with.
    public static let testedVersion = "1.5.0"
}

/// Getting `topo` from its releases, as the panel and Settings show it.
public enum TopoFetch: Sendable, Hashable {
    case idle
    /// `version` is known once the release is; `fraction` once its size is.
    case downloading(TopoBuild, version: String?, fraction: Double?)
    /// It failed; `next` is the build to offer now: the tested one when the
    /// latest couldn't be used.
    case failed(next: TopoBuild, TopoFetchProblem)

    public var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// Why a download didn't give a `topo` the app can run.
public enum TopoFetchProblem: Error, Sendable, Hashable {
    /// GitHub couldn't be reached: the system's own words.
    case unreachable(String)
    /// GitHub answered with this HTTP status.
    case status(Int)
    /// GitHub's description of the release can't be read.
    case unreadableRelease
    /// The release has no archive for this Mac.
    case noArchive(version: String)
    /// Neither GitHub nor the release says what the archive's hash is.
    case noChecksum(version: String)
    /// The archive isn't what the release says it is.
    case checksumMismatch(version: String)
    /// The archive couldn't be unpacked, or holds no `topo`.
    case unpack(version: String)
    /// The `topo` it holds doesn't speak what this app reads.
    case unusable(version: String, EngineProblem)
    /// It couldn't be saved.
    case storage(String)
}
