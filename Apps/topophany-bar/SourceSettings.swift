import AppKit
import SwiftUI
import TopophanyEngine
import TopophanyKit
import TopophanySections

/// Where readings come from and, in direct mode, the direct profile and
/// its Beszel sources: the same grouped form as every other Settings page.
struct SourceSettings: View {
    @Environment(AppModel.self) private var model
    @State private var profiles: [DirectProfile] = []
    @State private var selectedProfile = "desktop"
    @State private var naming = false
    @State private var client: SourcesClient?
    @State private var editor: SourceEditor?
    @State private var removing: DirectProfile.Entry?
    @State private var busy = false
    @State private var problem: String?
    @State private var supported = false
    @State private var checked = false
    @State private var listLoaded = false
    @State private var operation: Task<Void, Never>?
    /// The editor's height, which the window grows to hold while it's open.
    @State private var sheetHeight = 0.0

    private static let newProfile = "\u{0}new"

    var profile: DirectProfile? { profiles.first { $0.profile == selectedProfile } }
    var source: String { model.settings.topo.source }

    var body: some View {
        SettingsForm(minHeight: editor == nil ? 0 : sheetHeight + 20) {
            Section {
                Picker(selection: Binding(get: { source }, set: { model.selectSource($0) })) {
                    Text("Topophany collector").tag("client")
                    Text("Beszel direct").tag("direct")
                    Text("Preview").tag("preview")
                    if !["client", "direct", "preview"].contains(source) {
                        Text("Unsupported source").tag(source)
                    }
                } label: {
                    RowLabel("Read from", readFromSubtitle)
                }
            }
            if source == "direct" {
                if supported {
                    beszel
                } else if checked {
                    Section {
                        RowLabel("This topo can’t read Beszel", "Choose or download a newer topo")
                        TopoRow()
                    }
                } else {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Checking topo…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task {
            selectedProfile = source == "direct" && !model.settings.topo.profile.isEmpty ? model.settings.topo.profile : "desktop"
            reload()
        }
        .onChange(of: model.effectiveSettings.topo.path) { reload() }
        .sheet(item: $editor, onDismiss: { reload() }) { session in
            SourceEditorForm(editor: session, finish: { session.close(); editor = nil }, onHeight: { sheetHeight = $0 })
        }
        .confirmationDialog("Remove this source?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove source", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("Only this profile's source is removed. Systems in Beszel are kept.") }
        .onDisappear { operation?.cancel(); editor?.close() }
    }

    var readFromSubtitle: LocalizedStringKey {
        switch source {
        case "client": "A Topophany collector, through topo’s saved profile"
        case "direct": "Your Beszel Hub, read by topo; no collector needed"
        case "preview": "topo’s built-in example network"
        default: "This source isn’t supported; choose another"
        }
    }

    /// The direct profile, its sources, and adding one.
    var beszel: some View {
        Section {
            profileRow
            if naming {
                LabeledContent {
                    CommitField(prompt: "Profile ID", value: Binding(get: { "" }, set: { name in
                        if !name.isEmpty { selectedProfile = name }
                        naming = false
                    }))
                } label: {
                    RowLabel("New profile", "Saved when you add its first source")
                }
            }
            if let entries = profile?.sources, !entries.isEmpty {
                ForEach(entries) { entry in
                    SourceRow(entry: entry, status: status(entry), disabled: busy || !listLoaded,
                              edit: { edit(entry) }, signIn: { edit(entry, login: true) }, remove: { removing = entry })
                }
            } else if listLoaded {
                RowLabel("No sources yet", "Add a Beszel Hub, then choose its servers")
            }
            if let problem {
                Label(SourceMessages.problem(problem), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("Add Source…") { edit(nil) }
                    .disabled(busy || !listLoaded || (profile?.sources.count ?? 0) >= 64)
                Spacer()
                if model.capabilities?.direct?.retry == true {
                    Button("Retry Now") { model.retryDirect() }
                        .disabled(profile?.sources.isEmpty ?? true)
                }
            }
        } header: {
            HStack {
                Text(verbatim: "Beszel")
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help(Text("Refresh sources"))
                        .accessibilityLabel(Text("Refresh sources"))
                }
            }
        } footer: {
            Foot("Up to 20 servers per source and 256 per profile. Only the running bar reads them, and a TUI opened from it reads on its own. Widgets keep the last snapshot, with its time.")
        }
    }

    /// The saved profiles to choose from, or, before there are any, the
    /// name the first source is saved under.
    @ViewBuilder var profileRow: some View {
        let label = RowLabel("Profile", "Where topo keeps these sources and their sign-in")
        if profiles.isEmpty {
            LabeledContent {
                CommitField(prompt: "desktop", value: $selectedProfile).frame(width: 200)
            } label: {
                label
            }
        } else {
            Picker(selection: Binding(get: { selectedProfile }, set: choose)) {
                ForEach(profiles) { p in Text(verbatim: Self.title(p)).tag(p.profile) }
                if profile == nil { Text("\(selectedProfile) (new)").tag(selectedProfile) }
                Divider()
                Text("New Profile…").tag(Self.newProfile)
            } label: {
                label
            }
            .disabled(!listLoaded)
        }
    }

    /// "desktop — homelab", as General shows a collector's profile.
    static func title(_ p: DirectProfile) -> String { p.project.isEmpty ? p.profile : "\(p.profile) — \(p.project)" }

    func choose(_ name: String) {
        guard name != Self.newProfile else { naming = true; return }
        naming = false
        selectedProfile = name
        if let p = profiles.first(where: { $0.profile == name }) { model.useDirect(profile: p.profile, revision: p.profileRevision) }
    }

    /// What the running stream says of this source, while it reads this profile.
    func status(_ entry: DirectProfile.Entry) -> SourcesStatus.Source? {
        guard model.settings.topo.profile == selectedProfile, let s = model.panel.status.sources, s.isCurrent else { return nil }
        return s.value.sources.first { $0.id == entry.id }
    }

    func reload(preserveProblem: Bool = false) {
        operation?.cancel()
        listLoaded = false
        let path: String
        if case .success(let found) = model.located { path = found.path }
        else if case .running(let r) = model.engineStatus { path = r.path }
        else { supported = false; checked = true; return }
        busy = true
        operation = Task {
            let caps = await Task.detached { ProcessEngine.check(path) }.value
            guard !Task.isCancelled else { return }
            checked = true
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

/// One Beszel source: its name, its Hub, how many servers it reads and,
/// while the bar reads it, its state. Sign In… leads when that's what it
/// needs; the rest are in its menu.
struct SourceRow: View {
    var entry: DirectProfile.Entry
    var status: SourcesStatus.Source?
    var disabled: Bool
    var edit: () -> Void
    var signIn: () -> Void
    var remove: () -> Void

    var signInFirst: Bool { status?.state == "auth_required" }
    var needsLook: Bool { status.map { $0.state != "connected" && $0.state != "loading" } ?? false }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Button(signInFirst ? "Sign In…" as LocalizedStringKey : "Edit…", action: signInFirst ? signIn : edit)
                Menu {
                    Button("Edit…", action: edit)
                    Button("Sign In Again…", action: signIn)
                    Divider()
                    Button("Remove…", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                .accessibilityLabel(Text("More for \(entry.source.name)"))
            }
            .disabled(disabled)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.source.name).lineLimit(1)
                HStack(spacing: 0) {
                    Text(verbatim: Words.join([Self.host(entry.source.url), tr("\(entry.nodes.count) servers")]))
                    if let status {
                        Text(verbatim: " · ")
                        Text(verbatim: SourceMessages.state(status.state)).foregroundStyle(needsLook ? .orange : .secondary)
                    }
                }
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    /// "beszel.example.com:8090": the address without its scheme.
    static func host(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host() else { return url }
        return u.port.map { "\(host):\($0)" } ?? host
    }
}

/// Adding or editing a source: its Hub and sign-in, a test that lists the
/// servers it can see, and which of them to read. Sized to what it shows.
struct SourceEditorForm: View {
    @Bindable var editor: SourceEditor
    var finish: () -> Void
    var onHeight: (Double) -> Void = { _ in }
    @State private var height = 0.0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                form
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(height, 120), 600))
            Divider()
            HStack {
                if editor.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { editor.close(); finish() }.keyboardShortcut(.cancelAction)
                Button("Save") { editor.save() }.disabled(!editor.canSave).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
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

    var form: some View {
        Form {
            Section(editor.allowsSaved ? "Beszel source" as LocalizedStringKey : "New Beszel source") {
                TextField("Name", text: $editor.source.name, prompt: Text("Home"))
                TextField("Hub URL", text: $editor.source.url, prompt: Text(verbatim: "https://beszel.example.com"))
                Picker("Sign in with", selection: $editor.authentication) {
                    if editor.allowsSaved { Text("Saved sign-in").tag(SourceEditor.Authentication.saved) }
                    Text("Account and password").tag(SourceEditor.Authentication.password)
                    Text("API token").tag(SourceEditor.Authentication.token)
                }
                if editor.authentication == .password {
                    TextField("Account", text: $editor.identity, prompt: Text("Email"))
                    SecureField("Password", text: $editor.password)
                } else if editor.authentication == .token {
                    SecureField("Token", text: $editor.token)
                }
            }
            .disabled(editor.busy)
            Section {
                LabeledContent {
                    Button("Test") { editor.inspect() }
                        .disabled(editor.busy || editor.source.name.isEmpty || editor.source.url.isEmpty)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection")
                        connection.font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let result = editor.inspection { servers(result) }
            Section {
                DisclosureGroup("Advanced") {
                    LabeledContent {
                        HStack(spacing: 6) {
                            TextField("", text: $editor.source.caFile, prompt: Text("None")).labelsHidden()
                                .multilineTextAlignment(.trailing)
                            Button("Choose…") { chooseCA() }
                        }
                    } label: {
                        RowLabel("CA file", "A PEM file, for a Hub with its own certificate authority")
                    }
                    SecondsField(title: "Collect every", value: $editor.source.intervalSeconds, range: 1...86400)
                    SecondsField(title: "Time out after", value: $editor.source.timeoutSeconds, range: 1...300)
                    SecondsField(title: "Contact valid for", value: $editor.source.staleSeconds,
                                 range: max(1, editor.source.intervalSeconds)...604800)
                    SecondsField(title: "Samples valid for", value: $editor.source.maxAgeSeconds, range: 1...604800)
                }
            }
            .disabled(editor.busy)
            if editor.needsReview { review }
        }
    }

    /// Whether the Hub answered, and what it said.
    @ViewBuilder var connection: some View {
        if let problem = editor.problem {
            Text(verbatim: SourceMessages.problem(problem)).foregroundStyle(.orange)
        } else if editor.busy && editor.inspection == nil {
            Text("Testing…").foregroundStyle(.secondary)
        } else if let result = editor.inspection {
            Text("Verified · \(result.systems.count) servers visible").foregroundStyle(.secondary)
        } else {
            Text("Test it to choose its servers").foregroundStyle(.secondary)
        }
    }

    /// Every server the Hub lists, ticked when it's read.
    func servers(_ result: DirectInspection) -> some View {
        Section {
            if result.systems.isEmpty {
                Text("No servers are visible to this account").foregroundStyle(.secondary)
            }
            ForEach(result.systems) { system in
                Toggle(isOn: Binding(get: { editor.selected.contains(system.id) }, set: { on in
                    if on { editor.selected.insert(system.id) } else { editor.selected.remove(system.id) }
                })) {
                    HStack {
                        Text(verbatim: system.name).lineLimit(1)
                        Spacer()
                        Text(verbatim: system.id).font(.callout.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel(Text(verbatim: system.name + " · " + system.id))
                .disabled(editor.busy || (!editor.selected.contains(system.id) && editor.selected.count >= editor.selectionLimit))
            }
        } header: {
            HStack(spacing: 6) {
                Text("Servers")
                Text("\(editor.selected.count) of \(editor.selectionLimit) chosen").fontWeight(.regular).foregroundStyle(.tertiary)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if result.truncated { Foot("The Hub listed only some of its servers. More may be in Beszel.") }
                Foot("Readings can take a moment to arrive after saving.")
            }
        }
    }

    /// After a save that may or may not have landed: the profile as it is
    /// now, to look over before trying again.
    @ViewBuilder var review: some View {
        Section {
            if let saved = editor.currentProfile {
                ForEach(saved.sources) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.source.name)
                        Text(verbatim: Words.join([SourceRow.host(entry.source.url)] + entry.nodes.map(\.name)))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button("I’ve Reviewed It") { editor.acknowledgeReview() }
            }
        } header: {
            Text("Saved profile")
        } footer: {
            Foot("The profile was read again. Look it over before trying again; nothing is overwritten on its own.")
        }
    }

    func chooseCA() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = tr("Choose the Hub's certificate authority, as a PEM file")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editor.source.caFile = url.path
    }
}

/// A number of seconds, typed or stepped, within its range.
struct SecondsField: View {
    var title: LocalizedStringKey
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                          format: .number.grouping(.never))
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 72)
                Text("s").foregroundStyle(.secondary)
                Stepper("", value: $value, in: range).labelsHidden()
            }
        }
    }
}
