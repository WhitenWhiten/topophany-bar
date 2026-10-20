import Foundation
import TopophanyKit

/// The Status card's offer to download `topo`, while none can run: none
/// was found, or the one found is too old.
public struct TopoOffer: Sendable, Hashable {
    public enum State: Sendable, Hashable {
        case ready
        case downloading(fraction: Double?)
        case failed(TopoFetchProblem)
    }

    /// What the button downloads.
    public var build: TopoBuild
    /// Known for the tested build, and for the latest once GitHub said.
    public var version: String?
    public var state: State

    public init(build: TopoBuild, version: String?, state: State) {
        self.build = build
        self.version = version
        self.state = state
    }

    /// Offered only while no `topo` can run.
    public init?(engine: EngineCondition, fetch: TopoFetch) {
        switch engine {
        case .notFound, .tooOld: break
        case .starting, .running, .restarting, .stopped: return nil
        }
        func known(_ b: TopoBuild) -> String? { b == .tested ? TopoBuild.testedVersion : nil }
        switch fetch {
        case .idle: self.init(build: .latest, version: nil, state: .ready)
        case .downloading(let b, let v, let f): self.init(build: b, version: v ?? known(b), state: .downloading(fraction: f))
        case .failed(let next, let p): self.init(build: next, version: known(next), state: .failed(p))
        }
    }

    public var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    /// The button: "Download topo", "Download topo 1.3.0", "Downloading 42%".
    public var title: String {
        switch state {
        case .downloading(let f?): return tr("Downloading \(Self.percent(f))%")
        case .downloading(nil): return tr("Downloading…")
        case .ready, .failed: return build == .tested ? tr("Download topo \(TopoBuild.testedVersion)") : tr("Download topo")
        }
    }

    /// What stands in for the Status card's subtitle, when anything does.
    public var line: String? {
        switch state {
        case .ready: return nil
        case .downloading(let f): return Self.downloading(version, f)
        case .failed(let p): return Self.failed(p, next: build)
        }
    }

    /// The Terminal look's keycap words.
    public var keyWords: String {
        switch state {
        case .ready:
            return build == .tested ? tr("download topo \(TopoBuild.testedVersion), tested with this app")
                : tr("download topo from its latest release")
        case .downloading(let f): return Self.lowerFirst(Self.downloading(version, f))
        case .failed(let p): return Self.lowerFirst(Self.failed(p, next: build))
        }
    }

    /// "couldn’t reach GitHub": the Terminal look's lines start in lowercase,
    /// and names keep theirs.
    static func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    /// "Downloading topo 1.3.0 · 42%"
    public static func downloading(_ version: String?, _ fraction: Double?) -> String {
        switch (version, fraction) {
        case (let v?, let f?): tr("Downloading topo \(v) · \(percent(f))%")
        case (let v?, nil): tr("Downloading topo \(v)…")
        case (nil, _): tr("Looking for topo’s latest release…")
        }
    }

    /// Why it failed, and what to do next: try again, or try the tested
    /// release.
    public static func failed(_ p: TopoFetchProblem, next: TopoBuild) -> String {
        let then = next == .tested ? tr("try \(TopoBuild.testedVersion), tested with this app") : tr("try again")
        return tr("\(problem(p)) · \(then)")
    }

    public static func problem(_ p: TopoFetchProblem) -> String {
        switch p {
        case .unreachable: tr("Couldn’t reach GitHub")
        case .status(let code): tr("GitHub answered \(code)")
        case .unreadableRelease: tr("GitHub’s answer can’t be read")
        case .noArchive(let v): tr("topo \(v) has no build for this Mac")
        case .noChecksum(let v): tr("topo \(v) has no checksum, so it wasn’t kept")
        case .checksumMismatch(let v): tr("topo \(v) didn’t match its checksum, so it wasn’t kept")
        case .unpack(let v): tr("topo \(v)’s archive can’t be opened")
        case .unusable(let v, _): tr("topo \(v) doesn’t speak what this app reads")
        case .storage: tr("topo couldn’t be saved")
        }
    }

    static func percent(_ f: Double) -> Int { Int((max(0, min(1, f)) * 100).rounded(.down)) }
}
