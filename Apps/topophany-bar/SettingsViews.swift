import AppKit
import LocalReadings
import SwiftUI
import SystemConfiguration
import TopophanyEngine
import TopophanyKit
import TopophanySections
import TopophanyThemes

// MARK: shared parts

extension AppModel {
    /// A binding that saves through `update`, so each change reaches `topo`.
    func binding<T: Equatable>(_ path: WritableKeyPath<TopophanyKit.Settings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: path] },
                set: { v in self.update { $0[keyPath: path] = v } })
    }
}

/// The width every tab lays out in.
private let settingsWidth = 560.0

/// A row's title, and the line under it.
struct RowLabel: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    init(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// A section's icon: a white symbol on a colored rounded square.
struct IconTile: View {
    var symbol: String
    var color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
    }
}

/// A note under a group, as the previews set them.
struct Foot: View {
    var text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A text field that saves when the user presses Return or leaves it, not
/// on every keystroke: each save restarts or re-requests `topo`.
struct CommitField: View {
    var prompt: LocalizedStringKey
    @Binding var value: String
    var monospaced = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text(prompt))
            .font(monospaced ? .body.monospaced() : .body)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { value = draft.trimmingCharacters(in: .whitespaces) }
            .onChange(of: focused) { _, f in if !f { value = draft.trimmingCharacters(in: .whitespaces) } }
            .onAppear { draft = value }
            .onChange(of: value) { _, v in if !focused { draft = v } }
    }
}

/// Settings forms: grouped, fixed width, as tall as their content. The
/// window fits itself to that size (`fitSettings`), and the form stays at
/// the top while it does.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.fitSettings) private var fit

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: settingsWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { fit($0) }
            // While the window is still shorter than the form, the form
            // overflows at the bottom rather than being centered.
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
}

/// Where a tab's form reports its size.
struct SettingsFitter: Equatable {
    var tab = 0
    weak var tabs: SettingsTabs?

    @MainActor func callAsFunction(_ size: CGSize) { tabs?.fit(size, tab: tab) }

    static func == (a: Self, b: Self) -> Bool { a.tab == b.tab && a.tabs === b.tabs }
}

extension EnvironmentValues {
    @Entry var fitSettings = SettingsFitter()
}

/// "How often" choices, as `topo` durations.
let refreshChoices = ["1s", "2s", "5s", "10s", "30s", "1m", "5m", "15m", "1h"]

func everyText(_ d: String) -> String {
    guard let i = Interval(d) else { return d }
    let s = Int(i.seconds)
    if s < 60 { return tr("Every \(s) s") }
    if s < 3600 { return tr("Every \(s / 60) min") }
    return tr("Every \(s / 3600) h")
}

// MARK: General

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsForm {
            Section("Topophany") {
                TopoRow()
                ProfileRow()
                Picker(selection: model.binding(\.topo.observer)) {
                    Text("All observers").tag("")
                    let known = model.knownObservers
                    if !known.isEmpty { Divider() }
                    ForEach(known, id: \.id) { o in Text(o.name).tag(o.id) }
                    let current = model.settings.topo.observer
                    if !current.isEmpty, !known.contains(where: { $0.id == current }) { Text(current).tag(current) }
                } label: {
                    RowLabel("View", "What the collector shows from")
                }
            }
            Section {
                EngineRow()
                Picker(selection: model.binding(\.topo.interval)) {
                    ForEach(refreshChoices, id: \.self) { Text(everyText($0)).tag($0) }
                } label: {
                    RowLabel("Refresh", "How often topo reads the collector; deadlines are checked every second either way")
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Engine")
                    Text(verbatim: "topo monitor stream").fontWeight(.regular).foregroundStyle(.tertiary)
                }
            }
            Section("Startup") {
                Toggle(isOn: model.binding(\.openAtLogin)) { RowLabel("Open at login") }
                    .toggleStyle(.switch)
                TerminalPicker()
            }
            PanelShortcutSettings()
            Section {
                Picker(selection: model.binding(\.language)) {
                    Text("Match System").tag(TopophanyKit.Settings.Language.system)
                    Divider()
                    // Each language in its own words, as the system lists them.
                    Text(verbatim: "English").tag(TopophanyKit.Settings.Language.en)
                    Text(verbatim: "日本語").tag(TopophanyKit.Settings.Language.ja)
                    Text(verbatim: "简体中文").tag(TopophanyKit.Settings.Language.zhHans)
                } label: {
                    RowLabel("Language", "For the panel, the menu bar item, widgets and these settings")
                }
            }
        }
    }
}

/// The terminals installed that the TUI can open in, then any other app.
struct TerminalPicker: View {
    @Environment(AppModel.self) private var model
    private static let other = "\u{0}other"

    var body: some View {
        let chosen = model.settings.terminal
        let terminals = TerminalLauncher.terminals(chosen: chosen)
        Picker(selection: Binding(get: { TerminalLauncher.terminal(chosen: chosen)?.id ?? "" },
                                  set: { id in id == Self.other ? choose() : model.update { $0.terminal = id } })) {
            ForEach(terminals) { t in
                Label { Text(verbatim: t.name) } icon: { Image(nsImage: t.icon) }.tag(t.id)
            }
            Divider()
            Text("Other…").tag(Self.other)
        } label: {
            RowLabel("Open Topophany in", "Where ⌘O and “more in Topophany” open the TUI")
        }
    }

    /// Any app, which is given the TUI as a script to open.
    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = tr("Choose")
        panel.message = tr("Choose the terminal that opens the TUI. It's given a shell script to open.")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.update { $0.terminal = id }
    }
}

/// The saved profile to read through: a menu of those `topo` lists, or a
/// name typed in when this `topo` can't list them.
struct ProfileRow: View {
    @Environment(AppModel.self) private var model

    @State private var signingIn = false

    var body: some View {
        let label = RowLabel("Profile", "Saved by `topo login`; the app never sees a token")
        if model.profiles?.profiles.isEmpty == true {
            // topo lists profiles and has none: sign in with topo login.
            LabeledContent {
                Button("Sign In…") { signingIn = true }
                    .popover(isPresented: $signingIn, arrowEdge: .bottom) { Localized(content: SignInForm(open: $signingIn)).environment(model) }
            } label: {
                RowLabel("Profile", "No profile saved yet; topo keeps the token, never the app")
            }
        } else if let list = model.profiles {
            let chosen = model.settings.topo.profile
            Picker(selection: model.binding(\.topo.profile)) {
                Text(list.active.map { tr("Active: \(Self.title($0))") } ?? tr("Active profile")).tag("")
                Divider()
                ForEach(list.profiles) { p in Text(verbatim: Self.title(p)).tag(p.name) }
                if !chosen.isEmpty, !list.profiles.contains(where: { $0.name == chosen }) {
                    Text("\(chosen) (not saved)").tag(chosen)
                }
            } label: {
                label
            }
        } else {
            LabeledContent {
                CommitField(prompt: "Active profile", value: model.binding(\.topo.profile)).frame(width: 200)
            } label: {
                label
            }
        }
    }

    /// "home — homelab", as the previews show a profile.
    static func title(_ p: ProfileList.Profile) -> String { p.project.isEmpty ? p.name : "\(p.name) — \(p.project)" }
}

/// Signs in with `topo login`, in the user's terminal: the app asks only
/// where, and topo asks for the token there.
struct SignInForm: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Bool
    @State private var server = ""
    @State private var project = ""
    @State private var profile = "default"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in with topo login").font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 7) {
                GridRow {
                    Text("Server").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    TextField("", text: $server, prompt: Text(verbatim: "https://collector.example.com"))
                }
                GridRow {
                    Text("Project").foregroundStyle(.secondary)
                    TextField("", text: $project, prompt: Text(verbatim: "homelab"))
                }
                GridRow {
                    Text("Profile").foregroundStyle(.secondary)
                    TextField("", text: $profile)
                }
            }
            .textFieldStyle(.roundedBorder)
            Text("Your terminal opens and runs topo login, which asks for the token there. The app never sees it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { open = false }.keyboardShortcut(.cancelAction)
                Button("Continue in Terminal") {
                    TerminalLauncher.login(model: model, server: trimmed(server), project: trimmed(project),
                                           profile: trimmed(profile).isEmpty ? "default" : trimmed(profile))
                    open = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(server).isEmpty || trimmed(project).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 330)
        // Not the trailing alignment of the row it opens from.
        .multilineTextAlignment(.leading)
    }

    func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The `topo` executable: where it is and whether it speaks protocol 1.
/// Its menu runs any `topo` on this Mac, downloads one or deletes a
/// downloaded copy; while none can run, Download does it in one click.
struct TopoRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if !model.fetch.isDownloading {
                    if let path {
                        Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                            .font(.callout.monospaced())
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary.opacity(0.6)))
                    }
                    version
                    if let offer = model.panel.download {
                        Button { model.download(offer.build) } label: {
                            Label { Text(verbatim: offer.title) } icon: { Image(systemName: "arrow.down.circle") }
                        }
                        .buttonStyle(.borderedProminent)
                        .fixedSize()
                    }
                }
                menu
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("topo executable")
                switch model.fetch {
                case .downloading(_, let v, let f):
                    Text(verbatim: TopoOffer.downloading(v, f)).font(.callout).foregroundStyle(.secondary)
                    ProgressView(value: f ?? 0).progressViewStyle(.linear).controlSize(.small).padding(.top, 4)
                case .failed(let next, let p):
                    Text(verbatim: TopoOffer.failed(p, next: next)).font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                case .idle:
                    // A path wraps whole, never at its slashes.
                    Text(verbatim: subtitle.replacingOccurrences(of: "/", with: "/\u{2060}"))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Every `topo` on this Mac, the tested release and the latest, and
    /// the downloaded copies to delete.
    var menu: some View {
        Menu {
            Toggle("Search Automatically", isOn: Binding(get: { model.settings.topo.path.isEmpty },
                                                          set: { if $0 { model.use("") } }))
            if !model.candidates.isEmpty {
                Divider()
                Section("On this Mac") {
                    ForEach(model.candidates) { c in
                        Toggle(isOn: Binding(get: { model.settings.topo.path == c.path }, set: { if $0 { model.use(c.path) } })) {
                            Text(verbatim: Self.title(c))
                        }
                        .disabled(!c.isUsable)
                    }
                }
            }
            Divider()
            Button("Choose…") { choose() }
            Divider()
            Group {
                Button("Download Latest") { model.download(.latest) }
                Button("Download \(TopoBuild.testedVersion), Tested With This App") { model.download(.tested) }
            }
            .disabled(model.fetch.isDownloading)
            if !model.downloaded.isEmpty {
                Divider()
                Menu("Delete Download") {
                    ForEach(model.downloaded) { d in
                        Button { model.deleteDownload(d) } label: { Text(verbatim: "topo \(d.version)") }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        .accessibilityLabel(Text("Choose topo"))
    }

    /// "1.3.0 — ~/.local/bin/topo", "1.3.0 — Downloaded", or why it can't
    /// be used.
    static func title(_ c: TopoCandidate) -> String {
        let place = c.origin == .downloaded ? tr("Downloaded") : (c.path as NSString).abbreviatingWithTildeInPath
        let named = c.version.map { "\($0) — \(place)" } ?? place
        switch c.problem {
        case nil: return named
        case .upgradeNeeded?: return tr("\(named) (no monitor stream)")
        case .unsupported?, .launchFailed?, .notFound?: return tr("\(named) (can’t be read)")
        }
    }

    var path: String? {
        if case .running(let r) = model.engineStatus { return r.path }
        if case .success(let f)? = model.located { return f.path }
        return nil
    }

    @ViewBuilder var version: some View {
        switch model.engineStatus {
        case .running(let r):
            Text(verbatim: "\(r.version) ✓").font(.callout).foregroundStyle(.green)
        case .unavailable(.upgradeNeeded), .unavailable(.unsupported):
            Text("Too old").font(.callout).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    var subtitle: String {
        if model.fixture != nil { return tr("Replaying a fixture; topo is not running") }
        switch model.located {
        case .success(let f)? where f.origin == "downloaded" || model.downloaded.contains(where: { $0.path == f.path }):
            return tr("Downloaded by this app; every reading comes from it")
        case .success(let f)? where f.origin == "setting": return tr("Chosen here; every reading comes from it")
        case .success(let f)? where f.origin == "PATH": return tr("Found on PATH; every reading comes from it")
        case .success(let f)?: return tr("Found in \((f.path as NSString).deletingLastPathComponent); every reading comes from it")
        case .failure?: return tr("Not found on PATH, in /opt/homebrew/bin or /usr/local/bin")
        case nil: return tr("Looking for topo…")
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = tr("Choose the topo executable")
        panel.directoryURL = URL(filePath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.use(url.path)
    }
}

/// `topo monitor stream`: running, restarting or why not.
struct EngineRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { t in
            LabeledContent {
                Button("Restart") { model.restartEngine() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(dot).frame(width: 7, height: 7)
                        Text(verbatim: title)
                    }
                    Text(verbatim: detail(t.date)).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    var dot: Color {
        switch model.engineStatus {
        case .running: .green
        case .starting, .restarting: .orange
        case .unavailable, .stopped: .red
        }
    }

    var title: String {
        switch model.engineStatus {
        case .starting: tr("Starting")
        case .running: tr("Running")
        case .restarting: tr("Restarting")
        case .unavailable(.notFound): tr("topo not found")
        case .unavailable(.upgradeNeeded), .unavailable(.unsupported): tr("topo must be upgraded")
        case .unavailable(.launchFailed): tr("Could not start topo")
        case .stopped: tr("Stopped")
        }
    }

    func detail(_ now: Date) -> String {
        var parts: [String] = []
        switch model.engineStatus {
        case .running(let r):
            if r.pid > 0 { parts.append(tr("pid \(r.pid)")) }
        case .restarting(let after, let attempt, let reason):
            parts.append(reason)
            _ = after
            parts.append(tr("attempt \(attempt)"))
        case .unavailable(.notFound):
            parts.append(tr("Download topo, or choose one above"))
        case .unavailable(.upgradeNeeded):
            parts.append(tr("This topo has no monitor stream; download a newer one above"))
        case .unavailable(.unsupported(_, let version, let missing)):
            parts.append(tr("\(version) lacks \(missing.joined(separator: ", "))"))
        case .unavailable(.launchFailed(_, let message)):
            parts.append(message)
        default:
            break
        }
        if let at = model.lastFrameAt { parts.append(tr("last frame \(Words.ago(at, now: now))")) }
        if let lease = model.reading.frame?.publisherExpiresAt, model.reading.isLive {
            parts.append(tr("lease until \(lease.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: L10n.locale)))"))
        }
        if let last = model.diagnostics.last, parts.count < 2 { parts.append(last) }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}

// MARK: Appearance

struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsForm {
            Section {
                // One line; it scrolls when more themes than fit.
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(model.themes.themes, id: \.id) { t in ThemeChoice(theme: t) }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
            } header: {
                Text("Theme")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let blurb = model.theme.blurb {
                        Text(verbatim: blurb).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Foot("The theme applies to the panel, the menu bar item and every widget. A later release can add themes as files: a renderer's name and its tokens.")
                }
            }
            Section("Panel") {
                Picker(selection: model.binding(\.appearance.panel)) {
                    Text("Match System").tag(TopophanyKit.Settings.Appearance.Panel.system)
                    Text("Light").tag(TopophanyKit.Settings.Appearance.Panel.light)
                    Text("Dark").tag(TopophanyKit.Settings.Appearance.Panel.dark)
                } label: {
                    RowLabel("Appearance", "For themes that follow the system; the others keep their own")
                }
                .disabled(model.theme.appearance != .system)
                Picker(selection: model.binding(\.appearance.textSize)) {
                    Text("Small").tag(TopophanyKit.Settings.Appearance.TextSize.small)
                    Text("Default").tag(TopophanyKit.Settings.Appearance.TextSize.default)
                    Text("Large").tag(TopophanyKit.Settings.Appearance.TextSize.large)
                } label: {
                    RowLabel("Text size")
                }
                LabeledContent {
                    HStack(spacing: 10) {
                        if let h = model.settings.appearance.panelHeight {
                            Text("Up to \(h) pt").monospacedDigit().foregroundStyle(.secondary)
                            Button("Reset") { model.update { $0.appearance.panelHeight = nil } }
                        } else {
                            Text("Up to the screen’s height").foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    RowLabel("Height", "Drag the panel’s bottom edge; double-click it to reset")
                }
            }
            Section {
                LabeledContent {
                    Picker("", selection: model.binding(\.appearance.menuBar.show)) {
                        Text("Symbol").tag(TopophanyKit.Settings.Appearance.Show.symbol)
                        Text("Count").tag(TopophanyKit.Settings.Appearance.Show.count)
                        Text("Words").tag(TopophanyKit.Settings.Appearance.Show.words)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                } label: {
                    RowLabel("Show", "The count is what needs attention; nothing when all clear")
                }
                MenuBarIconSettings()
                Toggle(isOn: model.binding(\.appearance.menuBar.statusColors)) {
                    RowLabel("Status colors", "Off draws the badge in the menu bar’s own color; its shape still changes")
                }
                .toggleStyle(.switch)
                Toggle(isOn: model.binding(\.appearance.menuBar.motion)) {
                    RowLabel("Motion", "Turns while what it shows is current and rests when it isn’t; a change moves once")
                }
                .toggleStyle(.switch)
                LabeledContent {
                    HStack(spacing: 14) {
                        menuBarReading(.cpu, "CPU")
                        menuBarReading(.memory, "Memory")
                        menuBarReading(.network, "Network")
                    }
                    .toggleStyle(.checkbox)
                } label: {
                    RowLabel("This Mac", "Local readings beside the item, in the menu bar’s own color")
                }
                LabeledContent {
                    MenuBarPreview()
                } label: {
                    RowLabel("Preview")
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Foot("Reduce Motion and Low Power Mode keep the item still.")
            }
        }
    }
}

extension AppearanceSettings {
    func menuBarReading(_ r: TopophanyKit.Settings.Appearance.MenuBar.Reading, _ title: LocalizedStringKey) -> some View {
        Toggle(title, isOn: Binding(get: { model.settings.appearance.menuBar.readings.contains(r) },
                                    set: { on in model.update { $0.appearance.menuBar.setReading(r, on) } }))
    }
}

/// A theme, shown as its colors.
struct ThemeChoice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme
    var theme: Theme

    var selected: Bool { model.theme.id == theme.id }

    /// The light or dark the panel would draw this theme in now.
    var scheme: ColorScheme {
        switch model.settings.appearance.panel {
        case .light: .light
        case .dark: .dark
        case .system: systemScheme
        }
    }

    var body: some View {
        Button {
            model.update { $0.appearance.theme = theme.id }
        } label: {
            VStack(spacing: 5) {
                ThemeSwatch(theme: theme, colorScheme: scheme)
                    .frame(width: 68, height: 40)
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
                Text(verbatim: theme.title)
                    .font(.callout)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.blurb ?? "")
        .accessibilityLabel(theme.title)
        .accessibilityHint(theme.blurb ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension Theme {
    /// A built-in theme's name in the chosen language; a file's own name
    /// otherwise.
    var title: String {
        switch id {
        case "native": tr("Native")
        case "aurora": tr("Aurora")
        case "linen": tr("Linen")
        case "terminal": tr("Terminal")
        case "paper": tr("Paper")
        case "dusk": tr("Dusk")
        default: name
        }
    }

    /// How a built-in theme looks, in a sentence.
    var blurb: String? {
        switch id {
        case "native": tr("macOS glass, SF Pro and system colors, like the apps beside it.")
        case "aurora": tr("A northern sky at night: teal deepening to violet, round shapes, meters of dots.")
        case "linen": tr("A matte, woven page set in New York: ruled sections, small capitals, meters as scales.")
        case "terminal": tr("Topophany’s TUI: ink, phosphor and monospace, the same glyphs as topo.")
        case "paper": tr("Topophany’s TUI printed on warm paper: grain, rules and halftone meters.")
        case "dusk": tr("Topophany’s TUI at nightfall: pastels on deep indigo, boxes held by their corners, meters in braille.")
        default: nil
        }
    }
}

/// The menu bar item in each state, as the menu bar would draw it now.
struct MenuBarPreview: View {
    @Environment(AppModel.self) private var model

    static let statuses: [StatusSection] = FixtureEngine.Scenario.allCases
        .filter { [.clear, .degraded, .incidents, .incomplete, .offline].contains($0) }
        .map { sc in
            let s = TopophanyKit.Settings()
            let now = Date()
            let r = FixtureEngine.reading(sc, request: TemplateCompiler().request(for: s, revision: 0), origin: now, after: 4)
            return SectionBuilder.panel(PanelInput(reading: r, engine: .running, settings: s)).status
        }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = model.theme
        var appearance = model.settings.appearance.menuBar
        let readings = !appearance.readings.isEmpty
        let _ = appearance.readings = []
        let moves = appearance.motion && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
        // Drawn as a dark menu bar shows it. This Mac's readings go with
        // the item as it is now.
        TimelineView(.animation(minimumInterval: 1 / 15, paused: !moves)) { t in
            let time = t.date.timeIntervalSinceReferenceDate
            let motion = StatusItemMotion(moves: moves, turn: moves ? time * StatusItemTurn.speed : 0, time: time)
            VStack(alignment: .trailing, spacing: 4) {
                if readings { item(model.statusItem, theme, motion) }
                TrailingFlow(spacing: 10, lineSpacing: 4, maxWidth: 340) {
                    ForEach(Array(Self.statuses.enumerated()), id: \.offset) { _, st in
                        item(StatusItemModel(status: st, appearance: appearance), theme, motion)
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(white: 0.12)))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    /// An item turning with the others while what it shows is current.
    func item(_ m: StatusItemModel, _ theme: Theme, _ motion: StatusItemMotion) -> some View {
        var motion = motion
        if m.activity != .live { motion.turn = 0 }
        return Renderers.renderer(for: theme)
            .statusItem(m, context: StatusItemContext(theme: theme, menuBarIsDark: true, motion: motion, customIcon: model.customIconAnimation))
    }
}

/// Rows that wrap when they run out of room, as even as that room allows,
/// each against the trailing edge, as the previews' wrapping rows are. As
/// wide as its widest row, and no wider than `maxWidth`, which is also its
/// room when it is asked for its ideal size.
struct TrailingFlow: Layout {
    typealias Row = [(LayoutSubview, CGSize)]
    var spacing: Double
    var lineSpacing: Double
    var maxWidth = Double.infinity

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, room: proposal.width)
        let width = rows.map { width($0) }.max() ?? 0
        let height = rows.reduce(0) { $0 + height($1) } + lineSpacing * Double(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, room: proposal.width ?? bounds.width) {
            let h = height(row)
            var x = bounds.maxX - width(row)
            for (v, s) in row {
                v.place(at: CGPoint(x: x, y: y + (h - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += h + lineSpacing
        }
    }

    /// The fewest rows that fit, packed into the narrowest room that still
    /// needs no more of them.
    private func rows(_ subviews: Subviews, room proposed: CGFloat?) -> [Row] {
        let items = subviews.map { ($0, $0.sizeThatFits(.unspecified)) }
        let room = min(proposed.map { Double($0) } ?? .infinity, maxWidth)
        let count = pack(items, room).count
        var lo = items.map { Double($0.1.width) }.max() ?? 0, hi = min(room, width(items))
        guard lo < hi else { return pack(items, room) }
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if pack(items, mid).count <= count { hi = mid } else { lo = mid }
        }
        return pack(items, hi)
    }

    private func pack(_ items: Row, _ room: Double) -> [Row] {
        var rows: [Row] = []
        for item in items {
            if let last = rows.last, width(last) + spacing + item.1.width <= room {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows
    }

    private func width(_ row: Row) -> Double {
        row.reduce(0) { $0 + $1.1.width } + spacing * Double(max(0, row.count - 1))
    }

    private func height(_ row: Row) -> Double {
        row.map { Double($0.1.height) }.max() ?? 0
    }
}

// MARK: Sections

struct SectionsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let order = Array(model.settings.sections.order.dropFirst())
        SettingsForm {
            Section {
                LabeledContent {
                    Label("Always first", systemImage: "lock.fill").labelStyle(.titleAndIcon)
                        .font(.callout).foregroundStyle(.tertiary)
                } label: {
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 12)
                        IconTile(symbol: "globe", color: Color(red: 0.19, green: 0.82, blue: 0.35))
                        RowLabel("Status", "The verdict, checks by health, observers live")
                    }
                }
                ReorderableRows(ids: order) { rest in
                    model.update { $0.sections.order = [.status] + rest }
                } label: { id in
                    SectionLabel(id: id)
                } trailing: { id in
                    SectionControls(id: id)
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Panel sections")
                    Text("drag to reorder").fontWeight(.regular).foregroundStyle(.tertiary)
                }
            } footer: {
                Foot("Each section is a row set in the template the app sends to `topo monitor stream`. What makes an entry up, warn or down is set in `topology.json` (for example `max_disk_percent`), not here.")
            }
            Section("When the panel scrolls") {
                Toggle(isOn: model.binding(\.sections.pinStatus)) {
                    RowLabel("Keep Status pinned", "The rest scrolls beneath it")
                }
                .toggleStyle(.switch)
            }
        }
    }
}

/// A section's handle, icon and name.
struct SectionLabel: View {
    @Environment(AppModel.self) private var model
    var id: SectionID

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 12)
            IconTile(symbol: symbol, color: color)
            label
        }
    }

    var symbol: String {
        switch id {
        case .status: "globe"
        case .seen: "scope"
        case .attention: "exclamationmark.triangle.fill"
        case .applications: "square.stack.3d.up.fill"
        case .services: "waveform.path.ecg"
        case .fleet: "square.grid.2x2.fill"
        case .servers: "server.rack"
        case .zones: "clock.fill"
        case .map: "map.fill"
        case .mac: "apple.logo"
        }
    }

    var color: Color {
        switch id {
        case .status: Color(red: 0.19, green: 0.82, blue: 0.35)
        case .seen: Color(red: 0.37, green: 0.36, blue: 0.90)
        case .attention: Color(red: 1, green: 0.62, blue: 0.04)
        case .applications: Color(red: 0.04, green: 0.52, blue: 1)
        case .services: Color(red: 1, green: 0.22, blue: 0.37)
        case .fleet: Color(red: 0.35, green: 0.34, blue: 0.84)
        case .servers: Color(red: 0.56, green: 0.56, blue: 0.58)
        case .zones: Color(red: 0.19, green: 0.69, blue: 0.78)
        case .map: Color(red: 0.64, green: 0.52, blue: 0.37)
        case .mac: Color(red: 0.39, green: 0.82, blue: 1)
        }
    }

    @ViewBuilder var label: some View {
        switch id {
        case .status: RowLabel("Status", "The verdict, checks by health, observers live")
        case .seen: RowLabel("Seen from", "Which observers see a problem, and that the others don’t")
        case .attention: RowLabel("Needs attention", "Open incidents first, then anything else that needs a look")
        case .applications: RowLabel("Applications", "Services folded into the applications you declare")
        case .services: RowLabel("Services", "The card of each service you pin: who sees it, and how fast")
        case .fleet: RowLabel("Fleet", "Every server, edge and platform topo lists, by who runs it")
        case .servers: RowLabel("Servers", "The Servers-tab card of each server you pin")
        case .zones: RowLabel("Time zones", "The time where your servers are, and each one’s health")
        case .map where model.mapGraph: RowLabel("Map", "Where your servers are, and the lines between them")
        case .map: RowLabel("Map", "Your servers placed by name, until this topo sends its map")
        case .mac: RowLabel("This Mac", "Set up under This Mac")
        }
    }
}

/// A section's own controls, then its switch.
struct SectionControls: View {
    @Environment(AppModel.self) private var model
    var id: SectionID

    var body: some View {
        HStack(spacing: 10) {
            controls
            Toggle("", isOn: Binding(get: { model.settings.sections.isEnabled(id) },
                                     set: { on in model.update { $0.sections.setEnabled(id, on) } }))
                .toggleStyle(.switch).labelsHidden()
        }
    }

    @ViewBuilder var controls: some View {
        switch id {
        case .attention:
            Picker("", selection: model.binding(\.sections.attentionLimit)) {
                Text("3 rows").tag(3)
                Text("5 rows").tag(5)
            }
            .labelsHidden().fixedSize()
        case .applications:
            ApplicationsButton()
        case .services:
            ServicesButton()
        case .servers:
            ServersButton()
        case .zones:
            ZonesButton()
        case .map:
            MapFramePicker()
        default:
            EmptyView()
        }
    }
}

/// Whether the geographic map fits every place or shows the whole world.
struct MapFramePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("", selection: Binding(get: { model.settings.sections.mapFrame },
                                      set: { frame in model.update { $0.sections.mapFrame = frame } })) {
            Text("Geo, fitted").tag(Sections.MapFrame.fit)
            Text("Geo, whole world").tag(Sections.MapFrame.world)
        }
        .labelsHidden().fixedSize()
    }
}

/// Which applications the section shows: all, or those ticked.
struct ApplicationsButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button("Choose…") { open = true }
            .popover(isPresented: $open, arrowEdge: .bottom) { Localized(content: ApplicationsPicker()).environment(model) }
    }
}

/// Every application `topo` lists, in its order, ticked when the section
/// shows it; chosen IDs it doesn't list come last. None ticked would mean
/// all, so the last one ticked stays ticked: the section's switch hides it.
struct ApplicationsPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let known = model.knownApplications
        let only = model.settings.sections.applicationsOnly
        let missing = only.filter { id in !known.contains { $0.id == id } }
        let ticked = only.isEmpty ? known.map(\.id) : known.map(\.id).filter { only.contains($0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Applications shown").font(.headline)
                Spacer()
                Button("Show All") { model.update { $0.sections.applicationsOnly = [] } }
                    .disabled(only.isEmpty)
            }
            if known.isEmpty && missing.isEmpty {
                Text("Applications appear once topo lists them.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(known) { a in
                            Toggle(isOn: shownBinding(a.id, known)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: a.name).lineLimit(1)
                                    Text(verbatim: Words.join([a.id, a.environment, tr("\(a.services.count) services")]))
                                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(ticked == [a.id])
                        }
                        ForEach(missing, id: \.self) { id in
                            Toggle(isOn: shownBinding(id, known)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: id).font(.body.monospaced()).lineLimit(1)
                                    Text("Not listed now").font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(only == [id])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
                Foot("With every one ticked, the section also shows applications declared later.")
            }
        }
        // A popover takes its row's trailing alignment otherwise.
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(width: 340)
    }

    func shownBinding(_ id: String, _ known: [Application]) -> Binding<Bool> {
        Binding(get: {
                    let only = model.settings.sections.applicationsOnly
                    return only.isEmpty || only.contains(id)
                },
                set: { on in
                    model.update { s in
                        var set = s.sections.applicationsOnly.isEmpty ? known.map(\.id) : s.sections.applicationsOnly
                        set.removeAll { $0 == id }
                        if on { set.append(id) }
                        let all = !known.isEmpty && known.allSatisfy { set.contains($0.id) }
                        s.sections.applicationsOnly = all ? [] : set
                    }
                })
    }
}

/// The servers pinned, by node ID.
struct ServersButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button("Choose…") { open = true }
            .popover(isPresented: $open, arrowEdge: .bottom) { Localized(content: ServersPicker()).environment(model) }
    }
}

struct ServersPicker: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        let nodes = model.settings.sections.serverNodes
        let known = model.knownServers
        VStack(alignment: .leading, spacing: 10) {
            Text("Pinned servers").font(.headline)
            if known.isEmpty {
                typed(nodes)
            } else {
                listed(known, pinned: nodes)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    /// Every server `topo` lists, ticked when pinned, in its order; pinned
    /// nodes it doesn't list come last.
    func listed(_ known: [ServerListEntry], pinned: [String]) -> some View {
        let missing = pinned.filter { n in !known.contains { $0.id == n } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(known) { s in
                    Toggle(isOn: pinBinding(s.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: s.name).lineLimit(1)
                            Text(verbatim: Words.join([s.id, s.kind, s.place])).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                ForEach(missing, id: \.self) { n in
                    Toggle(isOn: pinBinding(n)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: n).font(.body.monospaced()).lineLimit(1)
                            Text("Not in the topology").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    func pinBinding(_ node: String) -> Binding<Bool> {
        Binding(get: { model.settings.sections.serverNodes.contains(node) },
                set: { on in
                    model.update { s in
                        s.sections.serverNodes.removeAll { $0 == node }
                        if on {
                            s.sections.serverNodes.append(node)
                            s.sections.servers = true
                        }
                    }
                })
    }

    /// Node IDs typed in, when this `topo` can't list its servers.
    @ViewBuilder func typed(_ nodes: [String]) -> some View {
        if nodes.isEmpty {
            Text("None yet").foregroundStyle(.secondary)
        }
        ForEach(nodes, id: \.self) { n in
            HStack {
                Text(verbatim: name(n)).lineLimit(1)
                if name(n) != n { Text(verbatim: n).font(.callout.monospaced()).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    model.update { $0.sections.serverNodes.removeAll { $0 == n } }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Unpin \(name(n))"))
            }
        }
        Divider()
        HStack {
            TextField("", text: $draft, prompt: Text("Node ID, as in topology.json"))
                .font(.body.monospaced())
                .onSubmit(add)
            Button("Pin", action: add).disabled(!TemplateCompiler.validNode(draft.trimmingCharacters(in: .whitespaces)))
        }
        Text("A node that isn't in the topology shows as such.").font(.callout).foregroundStyle(.secondary)
    }

    func name(_ node: String) -> String {
        model.panel.servers.first { $0.id == node && !$0.isMissing }?.name ?? node
    }

    func add() {
        let n = draft.trimmingCharacters(in: .whitespaces)
        guard TemplateCompiler.validNode(n) else { return }
        model.update { s in
            if !s.sections.serverNodes.contains(n) { s.sections.serverNodes.append(n) }
            s.sections.servers = true
        }
        draft = ""
    }
}

/// The services pinned, by ID.
struct ServicesButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button("Choose…") { open = true }
            .popover(isPresented: $open, arrowEdge: .bottom) { Localized(content: ServicesPicker()).environment(model) }
    }
}

/// Every service `topo` lists, under its application, ticked when pinned;
/// pinned services it doesn't list come last. Pinned ones show in the order
/// they were pinned.
struct ServicesPicker: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        let ids = model.settings.sections.serviceIDs
        let known = model.knownServices
        VStack(alignment: .leading, spacing: 10) {
            Text("Pinned services").font(.headline)
            if known.isEmpty {
                typed(ids)
            } else {
                listed(known, pinned: ids)
            }
            if !model.cardsServices {
                Foot("This topo doesn’t send service cards. Pinned services appear once it does.")
            }
        }
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(width: 340)
    }

    /// The services by application, in `topo`'s order.
    func listed(_ known: [ServiceListEntry], pinned: [String]) -> some View {
        let missing = pinned.filter { id in !known.contains { $0.id == id } }
        var apps: [String] = []
        for s in known where !apps.contains(s.application) { apps.append(s.application) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(apps, id: \.self) { app in
                    Text(verbatim: app.isEmpty ? tr("No application") : app)
                        .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, app == apps.first ? 0 : 4)
                    ForEach(known.filter { $0.application == app }) { s in
                        Toggle(isOn: pinBinding(s.id)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: s.name).lineLimit(1)
                                Text(verbatim: Words.join([s.id, s.host.map { tr("on \($0.name)") } ?? "",
                                                           s.monitored == false ? tr("not monitored") : ""]))
                                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                ForEach(missing, id: \.self) { id in
                    Toggle(isOn: pinBinding(id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: id).font(.body.monospaced()).lineLimit(1)
                            Text("Not in the topology").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    func pinBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { model.settings.sections.serviceIDs.contains(id) },
                set: { on in
                    model.update { s in
                        s.sections.serviceIDs.removeAll { $0 == id }
                        if on {
                            s.sections.serviceIDs.append(id)
                            s.sections.services = true
                        }
                    }
                })
    }

    /// Service IDs typed in, before `topo` lists any.
    @ViewBuilder func typed(_ ids: [String]) -> some View {
        if ids.isEmpty {
            Text("None yet").foregroundStyle(.secondary)
        }
        ForEach(ids, id: \.self) { id in
            HStack {
                Text(verbatim: name(id)).lineLimit(1)
                if name(id) != id { Text(verbatim: id).font(.callout.monospaced()).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    model.update { $0.sections.serviceIDs.removeAll { $0 == id } }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Unpin \(name(id))"))
            }
        }
        Divider()
        HStack {
            TextField("", text: $draft, prompt: Text("Service ID, as in topology.json"))
                .font(.body.monospaced())
                .onSubmit(add)
            Button("Pin", action: add).disabled(!TemplateCompiler.validNode(draft.trimmingCharacters(in: .whitespaces)))
        }
        Text("A service that isn't in the topology shows as such.").font(.callout).foregroundStyle(.secondary)
    }

    func name(_ id: String) -> String {
        model.panel.services.first { $0.id == id && !$0.isMissing }?.name ?? id
    }

    func add() {
        let id = draft.trimmingCharacters(in: .whitespaces)
        guard TemplateCompiler.validNode(id) else { return }
        model.update { s in
            if !s.sections.serviceIDs.contains(id) { s.sections.serviceIDs.append(id) }
            s.sections.services = true
        }
        draft = ""
    }
}

/// The time zone of each place, for Time zones.
struct ZonesButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button("Places…") { open = true }
            .popover(isPresented: $open, arrowEdge: .bottom) { Localized(content: ZonesPicker()).environment(model) }
    }
}

/// Every place `topo` names, and the zone its clock is read in: the one its
/// name suggests, until another is chosen.
struct ZonesPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let places = model.knownPlaces
        VStack(alignment: .leading, spacing: 10) {
            Text("Time zones by place").font(.headline)
            if places.isEmpty {
                Text("Places appear once topo lists its servers.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        ForEach(places, id: \.place) { p in
                            GridRow {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: p.place).lineLimit(1)
                                    Text(p.servers == 0 ? tr("Not listed now") : tr("\(p.servers) servers"))
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                ZoneMenu(place: p.place).gridColumnAlignment(.trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
            Foot("A place takes the zone its name suggests. Choose another when that’s wrong, or None to leave its servers out.")
        }
        // A popover takes its row's trailing alignment otherwise.
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(width: 380)
    }
}

/// One place's zone: the suggested one, none, or any zone by region.
struct ZoneMenu: View {
    @Environment(AppModel.self) private var model
    var place: String

    var body: some View {
        let chosen = model.settings.sections.placeZones[place]
        let suggested = PlaceZones.suggestion(for: place)
        Menu {
            if let suggested {
                Button { choose(nil) } label: {
                    item(chosen == nil, tr("Suggested: \(PlaceZones.city(suggested))"))
                }
            }
            Button { choose("") } label: { item(chosen == "" || (chosen == nil && suggested == nil), tr("None")) }
            Divider()
            ForEach(PlaceZones.regions, id: \.region) { r in
                Menu(Self.regionName(r.region)) {
                    ForEach(r.zones, id: \.self) { z in
                        Button { choose(z) } label: { item(chosen == z, PlaceZones.city(z)) }
                    }
                }
            }
        } label: {
            Text(verbatim: label(chosen: chosen, suggested: suggested))
        }
        .fixedSize()
    }

    func label(chosen: String?, suggested: String?) -> String {
        switch chosen {
        case ""?: tr("None")
        case let z?: PlaceZones.city(z)
        case nil: suggested.map { tr("\(PlaceZones.city($0)) (suggested)") } ?? tr("None")
        }
    }

    @ViewBuilder func item(_ on: Bool, _ title: String) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(verbatim: title) }
    }

    /// nil goes back to the suggestion; "" is none.
    func choose(_ zone: String?) {
        model.update { s in
            if let zone { s.sections.placeZones[place] = zone } else { s.sections.placeZones.removeValue(forKey: place) }
        }
    }

    static func regionName(_ r: String) -> String {
        switch r {
        case "Africa": tr("Africa")
        case "America": tr("Americas")
        case "Antarctica": tr("Antarctica")
        case "Asia": tr("Asia")
        case "Atlantic": tr("Atlantic")
        case "Australia": tr("Australia")
        case "Europe": tr("Europe")
        case "Indian": tr("Indian Ocean")
        case "Pacific": tr("Pacific")
        default: r
        }
    }
}

// MARK: This Mac

struct MacSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let mode = model.settings.sections.mac.mode
        SettingsForm {
            Section("Show this Mac") {
                HStack(spacing: 10) {
                    ModeCard(mode: .local, symbol: "cpu", title: "Local readings",
                             text: "Read from macOS by the app, live, like a menu bar meter.")
                    ModeCard(mode: .server, symbol: "server.rack", title: "As a server",
                             text: "This Mac’s card from the collector, as in the Servers tab.")
                    ModeCard(mode: .off, symbol: "power", title: "Off", text: "No This Mac section.")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
            }
            if mode == .local { LocalReadingsSettings() }
            if mode == .server { MacServerSettings() }
        }
    }
}

struct ModeCard: View {
    @Environment(AppModel.self) private var model
    var mode: Sections.MacMode
    var symbol: String
    var title: LocalizedStringKey
    var text: LocalizedStringKey

    var body: some View {
        let on = model.settings.sections.mac.mode == mode
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { model.update { $0.sections.mac.mode = mode } }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .white : .secondary)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary)))
                    .padding(.bottom, 4)
                Text(title).fontWeight(.medium)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary.opacity(on ? 0.5 : 0.25)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct LocalReadingsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            reading(.cpu, "CPU", "Total, system and user, with the last \(historyMinutes) min")
            reading(.memory, "Memory", "Pressure, app, wired and compressed, as Activity Monitor counts them") {}
            reading(.storage, "Storage", nil) {
                Picker("", selection: model.binding(\.sections.mac.volume)) {
                    Text("Startup disk").tag("")
                    ForEach(LocalReadingsMonitor.volumes(), id: \.path) { v in
                        if v.path != "/" { Text(verbatim: v.name).tag(v.path) }
                    }
                }
                .labelsHidden().fixedSize()
            }
            reading(.network, "Network", "Throughput and address") {
                Picker("", selection: model.binding(\.sections.mac.interface)) {
                    Text(automatic).tag("")
                    ForEach(LocalReadingsMonitor.interfaces(), id: \.name) { i in Text(verbatim: i.displayName).tag(i.name) }
                }
                .labelsHidden().fixedSize()
            }
            if model.machine.hasBattery {
                reading(.battery, "Battery", "Charge, state and time remaining")
            }
            Picker(selection: model.binding(\.sections.mac.every)) {
                ForEach(["1s", "2s", "5s", "10s"], id: \.self) { d in Text(verbatim: "\(Int(Interval(d)?.seconds ?? 2)) s").tag(d) }
            } label: {
                RowLabel("Sample every")
            }
        } header: {
            Text("Readings")
        } footer: {
            Foot("Local readings are not evidence: they have no health and no thresholds, are never sent to a collector, and keep updating while the collector is unreachable.")
        }
    }

    /// How far back the CPU's history reaches at the chosen rate.
    var historyMinutes: Int {
        let every = Interval(model.settings.sections.mac.every)?.seconds ?? 2
        return max(1, Int((every * Double(LocalSnapshot.historyLength) / 60).rounded()))
    }

    var automatic: String {
        if let name = model.localInterfaceName { return tr("Automatic (\(name))") }
        return tr("Automatic")
    }

    func reading(_ r: Sections.Reading, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey?) -> some View {
        reading(r, title, subtitle) {}
    }

    func reading<C: View>(_ r: Sections.Reading, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey?,
                          @ViewBuilder trailing: () -> C) -> some View {
        HStack {
            Toggle(isOn: Binding(get: { model.settings.sections.mac.readings.contains(r) },
                                 set: { on in
                                     model.update { s in
                                         s.sections.mac.readings.removeAll { $0 == r }
                                         if on {
                                             s.sections.mac.readings = Sections.Reading.allCases.filter {
                                                 $0 == r || s.sections.mac.readings.contains($0)
                                             }
                                         }
                                     }
                                 })) {
                RowLabel(title, subtitle)
            }
            .toggleStyle(.checkbox)
            Spacer()
            trailing()
        }
    }
}

struct MacServerSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            NodeRow()
            Toggle(isOn: model.binding(\.sections.mac.resources)) {
                RowLabel("Host resources", "From the node’s host check, against its own limits")
            }
            .toggleStyle(.checkbox)
            Toggle(isOn: model.binding(\.sections.mac.services)) {
                RowLabel("Services", "The services declared on this node")
            }
            .toggleStyle(.checkbox)
            Toggle(isOn: model.binding(\.sections.mac.observes)) {
                RowLabel("Observes from here", "What this Mac’s observer sees: “is it me?”")
            }
            .toggleStyle(.checkbox)
        } header: {
            Text("Server")
        } footer: {
            Foot("This is the card everyone else sees for this Mac, read from the collector. Without a host check on the node, its resources read *unknown*, never zero.")
        }
    }
}

/// This Mac's node: a menu of the servers `topo` lists, the one matching
/// this Mac's name marked, or an ID typed in when it can't list them.
struct NodeRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let known = model.knownServers
        let node = model.settings.sections.mac.node
        if known.isEmpty {
            LabeledContent {
                CommitField(prompt: "Node ID", value: model.binding(\.sections.mac.node), monospaced: true).frame(width: 200)
            } label: {
                RowLabel("Node", subtitle(nil))
            }
        } else {
            let suggestion = Self.suggested(known)
            Picker(selection: model.binding(\.sections.mac.node)) {
                if node.isEmpty { Text("Choose a node").tag("") }
                ForEach(known) { s in
                    let title = Words.join([s.name, s.id, s.place])
                    Text(verbatim: s.id == suggestion?.id ? tr("\(title) (matches this Mac)") : title).tag(s.id)
                }
                if !node.isEmpty, !known.contains(where: { $0.id == node }) {
                    Text("\(node) (not in the topology)").tag(node)
                }
            } label: {
                RowLabel("Node", subtitle(node.isEmpty ? suggestion : nil))
            }
        }
    }

    func subtitle(_ suggestion: ServerListEntry?) -> LocalizedStringKey {
        if let suggestion { return "Suggested: \(suggestion.name), which matches this Mac’s name" }
        if case .server(let c, _)? = model.panel.mac {
            if c.isMissing { return "Not in the topology" }
            return "\(Words.join([c.name, c.kind, c.place]))"
        }
        return "The node’s ID in topology.json"
    }

    /// The node whose ID or name matches this Mac's `LocalHostName`.
    static func suggested(_ known: [ServerListEntry]) -> ServerListEntry? {
        guard let host = SCDynamicStoreCopyLocalHostName(nil) as String? else { return nil }
        return ServerListEntry.matching(localHostName: host, in: known)
    }
}
