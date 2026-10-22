import SwiftUI
import TopophanyEngine
import TopophanyKit
import TopophanySections

/// Uses the same grouped form and toolbar window as every other Settings page.
struct SourceSettings: View {
    @Environment(AppModel.self) private var model
    @State private var profiles: [DirectProfile] = []
    @State private var selectedProfile = "desktop"
    @State private var client: SourcesClient?
    @State private var editor: SourceEditor?
    @State private var removing: DirectProfile.Entry?
    @State private var busy = false
    @State private var problem: String?
    @State private var supported = false
    @State private var listLoaded = false
    @State private var operation: Task<Void, Never>?

    var profile: DirectProfile? { profiles.first { $0.profile == selectedProfile } }
    var body: some View {
        SettingsForm {
            Section("Data sources") {
                Picker("Read from", selection: Binding(get: { model.settings.topo.source }, set: { model.selectSource($0) })) {
                    Text("Topophany collector").tag("client")
                    Text("Beszel direct").tag("direct")
                    Text("Preview").tag("preview")
                    if !["client", "direct", "preview"].contains(model.settings.topo.source) {
                        Text("Unsupported source").tag(model.settings.topo.source)
                    }
                }
                Foot("Beszel direct connects topo to your Beszel Hub. No Topophany collector is needed.")
            }
            if model.settings.topo.source == "direct" {
                if supported {
                    Section("Direct profile") {
                        if !profiles.isEmpty {
                            Picker("Profile", selection: $selectedProfile) {
                                ForEach(profiles) { p in Text(verbatim: p.profile).tag(p.profile) }
                                if !profiles.contains(where: { $0.profile == selectedProfile }) { Text(verbatim: selectedProfile).tag(selectedProfile) }
                            }
                        }
                        CommitField(prompt: "Profile ID", value: $selectedProfile)
                        HStack {
                            Button("Use profile") { model.useDirect(profile: selectedProfile, revision: profile?.profileRevision ?? "") }
                                .disabled(profile == nil || !listLoaded)
                            Spacer()
                            Button("Refresh sources") { reload() }.disabled(busy)
                        }
                    }
                    Section("Beszel sources") {
                        if let profile, !profile.sources.isEmpty {
                            ForEach(profile.sources) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: entry.source.name).lineLimit(1)
                                        Text(verbatim: entry.source.url).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Edit…") { edit(entry) }.disabled(busy || !listLoaded)
                                    Button("Sign in…") { edit(entry, login: true) }.disabled(busy || !listLoaded)
                                    Button(role: .destructive) { removing = entry } label: { Image(systemName: "minus.circle") }
                                        .accessibilityLabel(Text("Remove source")).disabled(busy || !listLoaded)
                                }
                            }
                        } else { Foot("Add a Beszel source to choose servers and view resources.") }
                        Button("Add Beszel…") { edit(nil) }.disabled(busy || !listLoaded || (profile?.sources.count ?? 0) >= 64)
                        Button("Retry sources") { model.retryDirect() }.disabled(model.capabilities?.direct?.retry != true)
                        Foot("Each source can select up to 20 servers, with up to 256 per profile. Saving keeps other sources.")
                    }
                    Foot("Closing the bar stops its collection. A terminal window polls independently. Widgets show resource snapshots.")
                } else {
                    Section {
                        Foot("This topo does not support Beszel direct. Choose or download a newer topo in General.")
                        TopoRow()
                    }
                }
                if let problem { Text(verbatim: SourceMessages.problem(problem)).font(.callout).foregroundStyle(.secondary) }
                if busy { ProgressView().controlSize(.small) }
            }
        }
        .task { selectedProfile = model.settings.topo.source == "direct" && !model.settings.topo.profile.isEmpty ? model.settings.topo.profile : "desktop"; reload() }
        .onChange(of: model.effectiveSettings.topo.path) { reload() }
        .sheet(item: $editor, onDismiss: { reload() }) { session in
            SourceEditorForm(editor: session, finish: { session.close(); editor = nil })
        }
        .confirmationDialog("Remove this source?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove source", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("Only this profile's source is removed. Systems in Beszel are kept.") }
        .onDisappear { operation?.cancel(); editor?.close() }
    }
    func reload(preserveProblem: Bool = false) {
        operation?.cancel()
        listLoaded = false
        let path: String
        if case .success(let found) = model.located { path = found.path }
        else if case .running(let r) = model.engineStatus { path = r.path }
        else { supported = false; return }
        busy = true
        operation = Task {
            let caps = await Task.detached { ProcessEngine.check(path) }.value
            guard !Task.isCancelled else { return }
            guard case .success(let c) = caps, c.supports(source: "direct") else { supported = false; busy = false; return }
            supported = true
            let client = model.sourcesClient(path: path)
            self.client = client
            do {
                let list = try await client.call(.list, as: DirectProfiles.self)
                guard !Task.isCancelled else { return }
                profiles = list.profiles; listLoaded = true; if !preserveProblem { problem = nil }
            } catch { if !Task.isCancelled { problem = (error as? SourceProblem)?.code ?? "profile_unavailable" } }
            if !Task.isCancelled { busy = false }
        }
    }
    func edit(_ entry: DirectProfile.Entry?, login: Bool = false) {
        guard let client else { return }
        let editor = SourceEditor(client: client, profile: selectedProfile, revision: profile?.profileRevision ?? "", entry: entry)
        if login { editor.authentication = .password }
        editor.onSaved = { saved in
            model.useDirect(profile: saved.profile, revision: saved.profileRevision, nodes: saved.nodes.map(\.id), sourceID: saved.sourceID, retry: login)
            editor.close(); self.editor = nil
        }
        self.editor = editor
    }
    func remove() {
        guard let entry = removing, let client, let profile else { return }
        removing = nil; busy = true
        operation = Task {
            do {
                let result = try await client.call(.remove, SourceCommandRequest(profile: selectedProfile, baseRevision: profile.profileRevision, sourceID: entry.id), as: DirectRemoved.self)
                guard !Task.isCancelled else { return }
                model.removeDirectSource(result)
                problem = nil
            } catch { problem = (error as? SourceProblem)?.code ?? "profile_unavailable" }
            reload(preserveProblem: problem != nil)
        }
    }
}

struct SourceEditorForm: View {
    @Bindable var editor: SourceEditor
    var finish: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Beszel source") {
                    TextField("Name", text: $editor.source.name)
                    TextField("Hub URL", text: $editor.source.url)
                    Picker("Authentication", selection: $editor.authentication) {
                        Text("Account and password").tag(SourceEditor.Authentication.password)
                        Text("Token (advanced)").tag(SourceEditor.Authentication.token)
                        if editor.allowsSaved { Text("Saved sign-in").tag(SourceEditor.Authentication.saved) }
                    }
                    if editor.authentication == .password {
                        TextField("Account", text: $editor.identity)
                        SecureField("Password", text: $editor.password)
                    } else if editor.authentication == .token { SecureField("Token", text: $editor.token) }
                    DisclosureGroup("Advanced") {
                        TextField("CA file", text: $editor.source.caFile)
                        Stepper("Collection seconds: \(editor.source.intervalSeconds)", value: $editor.source.intervalSeconds, in: 1...86400)
                        Stepper("Timeout seconds: \(editor.source.timeoutSeconds)", value: $editor.source.timeoutSeconds, in: 1...300)
                        Stepper("Stale seconds: \(editor.source.staleSeconds)", value: $editor.source.staleSeconds, in: max(1, editor.source.intervalSeconds)...604800)
                        Stepper("Maximum age seconds: \(editor.source.maxAgeSeconds)", value: $editor.source.maxAgeSeconds, in: 1...604800)
                    }
                    Button("Test connection") { editor.inspect() }.disabled(editor.busy || editor.source.name.isEmpty || editor.source.url.isEmpty)
                }.disabled(editor.busy)
                if let result = editor.inspection {
                    Section {
                        if result.systems.isEmpty { Foot("Connected, but no systems are visible to this account.") }
                        ForEach(result.systems) { system in
                            Toggle(isOn: Binding(get: { editor.selected.contains(system.id) }, set: { on in
                                if on { editor.selected.insert(system.id) } else { editor.selected.remove(system.id) }
                            })) {
                                VStack(alignment: .leading) {
                                    Text(verbatim: system.name)
                                    Text(verbatim: system.id).font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityLabel(Text(verbatim: system.name + " · " + system.id))
                            .disabled(editor.busy || (!editor.selected.contains(system.id) && editor.selected.count >= editor.selectionLimit))
                        }
                    } header: { Text(verbatim: editor.source.name) }
                    if result.truncated { Foot("Discovery returned a limited list. More systems may be available in Beszel.") }
                    Foot("Connection verified. Resource samples may arrive after saving.")
                }
                if let problem = editor.problem { Text(verbatim: SourceMessages.problem(problem)).foregroundStyle(.secondary) }
                if editor.needsReview {
                    Foot("The saved profile was read again. Review your source and selection before retrying; no changes are overwritten automatically.")
                    if let saved = editor.currentProfile {
                        DisclosureGroup("Saved profile") {
                            ForEach(saved.sources) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: entry.source.name)
                                    Text(verbatim: entry.source.url).font(.callout).foregroundStyle(.secondary)
                                    ForEach(entry.nodes) { node in Text(verbatim: node.name + " · " + node.objectID).font(.caption) }
                                }
                            }
                        }
                    }
                    Button("I have reviewed the profile") { editor.acknowledgeReview() }
                }
            }
            .formStyle(.grouped)
            .frame(width: 520, height: 500)
            Divider()
            HStack {
                if editor.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { editor.close(); finish() }.keyboardShortcut(.cancelAction)
                Button("Save") { editor.save() }.disabled(!editor.canSave).keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .onChange(of: editor.source) {
            if editor.source.staleSeconds < editor.source.intervalSeconds { editor.source.staleSeconds = editor.source.intervalSeconds }
            editor.changed()
        }
        .onChange(of: editor.authentication) { editor.clearSecrets(); editor.changed() }
        .onChange(of: editor.identity) { editor.changed() }
        .onChange(of: editor.password) { editor.changed() }
        .onChange(of: editor.token) { editor.changed() }
        .onDisappear { editor.close() }
    }
}
