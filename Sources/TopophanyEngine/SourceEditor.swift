import Foundation
import Observation
import TopophanyKit

/// An editing session owns secrets; it is never Codable and is discarded on dismissal.
@MainActor @Observable
public final class SourceEditor: Identifiable {
    public let id = UUID()
    public enum Authentication: String, CaseIterable { case saved, password, token }
    public var source: DirectSource
    public var authentication: Authentication
    public var identity = ""
    public var password = ""
    public var token = ""
    public var selected: Set<String>
    public private(set) var inspection: DirectInspection?
    public private(set) var busy = false
    public private(set) var problem: String?
    public private(set) var revision: String
    public private(set) var needsReview = false
    public private(set) var currentProfile: DirectProfile?
    public let allowsSaved: Bool
    public let profile: String
    @ObservationIgnored private let savedURL: String?
    @ObservationIgnored private let client: SourcesClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var closed = false
    @ObservationIgnored public var onSaved: ((DirectSaved) -> Void)?
    public init(client: SourcesClient, profile: String, revision: String, entry: DirectProfile.Entry? = nil) {
        self.savedURL = entry?.source.url
        self.allowsSaved = entry != nil
        self.client = client; self.profile = profile; self.revision = revision
        source = entry?.source ?? DirectSource()
        authentication = entry == nil ? .password : .saved
        selected = Set(entry?.selectedObjects ?? [])
    }
    public var selectionLimit: Int { min(20, inspection?.limits.maxSelected ?? 20) }
    public var canSave: Bool { !busy && !needsReview && inspection != nil && !selected.isEmpty && selected.count <= selectionLimit }
    private var auth: SourceAuth {
        switch authentication {
        case .saved: .saved
        case .password: .password(identity: identity, password: password)
        case .token: .token(token)
        }
    }
    /// Called for authentication/URL/collection edits. A late discovery cannot replace the new form.
    public func changed() {
        generation += 1; operation?.cancel(); operation = nil
        inspection = nil; problem = nil; busy = false
    }
    public func clearSecrets() { password = ""; token = ""; identity = "" }
    public func close() {
        closed = true; generation += 1; operation?.cancel(); operation = nil; busy = false; clearSecrets(); onSaved = nil
    }
    public func inspect() {
        guard !busy, !closed else { return }
        if authentication == .saved, savedURL != source.url { problem = "hub_changed"; return }
        generation += 1
        let g = generation
        let request = SourceCommandRequest(profile: profile, source: source, auth: auth)
        busy = true; problem = nil; inspection = nil
        operation = Task { [weak self, client] in
            do {
                let result = try await client.call(.inspect, request, as: DirectInspection.self)
                guard let self, !self.closed, self.generation == g else { return }
                self.inspection = result
                let ids = Set(result.systems.map(\.id))
                self.selected.formIntersection(ids)
                self.busy = false
            } catch {
                guard let self, !self.closed, self.generation == g else { return }
                self.problem = (error as? SourceProblem)?.code ?? "command_cancelled"; self.busy = false
            }
        }
    }
    public func acknowledgeReview() { needsReview = false }
    public func save() {
        guard canSave, !closed else { return }
        generation += 1
        let g = generation
        let request = SourceCommandRequest(profile: profile, baseRevision: revision, source: source, auth: auth, selectedObjects: selected.sorted())
        busy = true; problem = nil
        operation = Task { [weak self, client] in
            do {
                let saved = try await client.call(.save, request, as: DirectSaved.self)
                guard let self, !self.closed, self.generation == g else { return }
                self.busy = false; self.clearSecrets(); self.onSaved?(saved)
            } catch {
                guard let self, !self.closed, self.generation == g else { return }
                let code = (error as? SourceProblem)?.code ?? "command_cancelled"
                self.problem = code
                // Failure may follow a committed write. Read before any retry and keep the same source ID.
                if ["profile_conflict", "command_timeout", "command_cancelled", "invalid_response", "output_limit"].contains(code) {
                    self.needsReview = true
                    do {
                        let list = try await client.call(.list, as: DirectProfiles.self)
                        guard !self.closed, self.generation == g else { return }
                        self.currentProfile = list.profiles.first { $0.profile == self.profile }
                        self.revision = self.currentProfile?.profileRevision ?? ""
                    } catch { self.problem = "profile_unavailable" }
                }
                self.busy = false
            }
        }
    }
}
