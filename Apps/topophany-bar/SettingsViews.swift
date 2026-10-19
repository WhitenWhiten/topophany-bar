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
    if s < 60 { return String(localized: "Every \(s) s") }
    if s < 3600 { return String(localized: "Every \(s / 60) min") }
    return String(localized: "Every \(s / 3600) h")
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
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the terminal that opens the TUI. It's given a shell script to open.")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.update { $0.terminal = id }
    }
}

/// The saved profile to read through: a menu of those `topo` lists, or a
/// name typed in when this `topo` can't list them.
struct ProfileRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let label = RowLabel("Profile", "Saved by `topo login`; the app never sees a token")
        if let list = model.profiles, !list.profiles.isEmpty {
            let chosen = model.settings.topo.profile
            Picker(selection: model.binding(\.topo.profile)) {
                Text(list.active.map { String(localized: "Active: \(Self.title($0))") } ?? String(localized: "Active profile")).tag("")
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

/// The `topo` executable: where it is and whether it speaks protocol 1.
struct TopoRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let path {
                    Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                        .font(.callout.monospaced())
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary.opacity(0.6)))
                }
                version
                Menu {
                    Button("Choose…") { choose() }
                    if !model.settings.topo.path.isEmpty {
                        Button("Search Automatically") { model.update { $0.topo.path = "" } }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                .accessibilityLabel(Text("Choose topo"))
            }
        } label: {
            RowLabel("topo executable", subtitle)
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
            Text("Upgrade needed").font(.callout).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    var subtitle: LocalizedStringKey {
        if model.fixture != nil { return "Replaying a fixture; topo is not running" }
        switch model.located {
        case .success(let f)? where f.origin == "setting": return "Chosen here; every reading comes from it"
        case .success(let f)? where f.origin == "PATH": return "Found on PATH; every reading comes from it"
        case .success(let f)?: return "Found in \((f.path as NSString).deletingLastPathComponent); every reading comes from it"
        case .failure?: return "Not found on PATH, in /opt/homebrew/bin or /usr/local/bin"
        case nil: return "Looking for topo…"
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = String(localized: "Choose the topo executable")
        panel.directoryURL = URL(filePath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { $0.topo.path = url.path }
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
        case .starting: String(localized: "Starting")
        case .running: String(localized: "Running")
        case .restarting: String(localized: "Restarting")
        case .unavailable(.notFound): String(localized: "topo not found")
        case .unavailable(.upgradeNeeded), .unavailable(.unsupported): String(localized: "topo must be upgraded")
        case .unavailable(.launchFailed): String(localized: "Could not start topo")
        case .stopped: String(localized: "Stopped")
        }
    }

    func detail(_ now: Date) -> String {
        var parts: [String] = []
        switch model.engineStatus {
        case .running(let r):
            if r.pid > 0 { parts.append(String(localized: "pid \(r.pid)")) }
        case .restarting(let after, let attempt, let reason):
            parts.append(reason)
            _ = after
            parts.append(String(localized: "attempt \(attempt)"))
        case .unavailable(.notFound):
            parts.append(String(localized: "Install topo, or choose it above"))
        case .unavailable(.upgradeNeeded):
            parts.append(String(localized: "This topo has no monitor stream; upgrade it"))
        case .unavailable(.unsupported(_, let version, let missing)):
            parts.append(String(localized: "\(version) lacks \(missing.joined(separator: ", "))"))
        case .unavailable(.launchFailed(_, let message)):
            parts.append(message)
        default:
            break
        }
        if let at = model.lastFrameAt { parts.append(String(localized: "last frame \(Words.ago(at, now: now))")) }
        if let lease = model.reading.frame?.publisherExpiresAt, model.reading.isLive {
            parts.append(String(localized: "lease until \(lease.formatted(date: .omitted, time: .standard))"))
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
                HStack(spacing: 12) {
                    ForEach(ThemeStore.builtIn, id: \.id) { t in ThemeChoice(theme: t) }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Theme")
            } footer: {
                Foot("The theme applies to the panel, the menu bar item and every widget. A later release can add themes as files: a renderer's name and its tokens.")
            }
            Section("Panel") {
                Picker(selection: model.binding(\.appearance.panel)) {
                    Text("Match System").tag(TopophanyKit.Settings.Appearance.Panel.system)
                    Text("Light").tag(TopophanyKit.Settings.Appearance.Panel.light)
                    Text("Dark").tag(TopophanyKit.Settings.Appearance.Panel.dark)
                } label: {
                    RowLabel("Appearance", "Native theme only; Terminal always paints its ink")
                }
                .disabled(model.theme.renderer == .cells)
                Picker(selection: model.binding(\.appearance.textSize)) {
                    Text("Small").tag(TopophanyKit.Settings.Appearance.TextSize.small)
                    Text("Default").tag(TopophanyKit.Settings.Appearance.TextSize.default)
                    Text("Large").tag(TopophanyKit.Settings.Appearance.TextSize.large)
                } label: {
                    RowLabel("Text size")
                }
            }
            Section("Menu bar") {
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
                Toggle(isOn: model.binding(\.appearance.menuBar.statusColors)) {
                    RowLabel("Status colors", "Off draws the badge in the menu bar’s own color; its shape still changes")
                }
                .toggleStyle(.switch)
                LabeledContent {
                    MenuBarPreview()
                } label: {
                    RowLabel("Preview")
                }
            }
        }
    }
}

/// A theme, shown as the real panel it draws.
struct ThemeChoice: View {
    @Environment(AppModel.self) private var model
    var theme: Theme

    var selected: Bool { model.theme.id == theme.id }

    var body: some View {
        Button {
            model.update { $0.appearance.theme = theme.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ThemeThumbnail(theme: theme)
                    .frame(height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1))
                HStack(spacing: 6) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text(verbatim: theme.id == "terminal" ? String(localized: "Terminal") : String(localized: "Native"))
                        .fontWeight(.medium)
                }
                Text(theme.id == "terminal"
                     ? "Topophany’s TUI: ink, phosphor and monospace, the same glyphs as topo."
                     : "macOS glass, SF Pro and system colors, like the apps beside it.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The top of the panel in a theme, drawn from the incidents fixture.
struct ThemeThumbnail: View {
    var theme: Theme

    static let model: PanelModel = {
        var s = TopophanyKit.Settings()
        s.sections.applications = false
        s.sections.mac.mode = .off
        s.sections.attentionLimit = 3
        let now = Date()
        let r = FixtureEngine.reading(.incidents, request: TemplateCompiler().request(for: s, revision: 0), origin: now, after: 4)
        return SectionBuilder.panel(PanelInput(reading: r, engine: .running, settings: s))
    }()

    static let scale = 0.6

    var body: some View {
        let ctx = RenderContext(theme: theme, colorScheme: .dark)
        GeometryReader { g in
            Renderers.renderer(for: theme).panel(Self.model, context: ctx)
                .environment(\.colorScheme, .dark)
                .fixedSize()
                .scaleEffect(Self.scale, anchor: .top)
                // Scaling leaves the layout size alone; the frame reports
                // the thumbnail's own size instead.
                .frame(width: g.size.width, height: g.size.height, alignment: .top)
                .padding(.top, 10)
                .allowsHitTesting(false)
        }
        .background(LinearGradient(colors: [Color(red: 0.23, green: 0.25, blue: 0.55), Color(red: 0.35, green: 0.18, blue: 0.45),
                                            Color(red: 0.06, green: 0.32, blue: 0.36)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipped()
        .accessibilityHidden(true)
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

    var body: some View {
        let theme = model.theme
        let appearance = model.settings.appearance.menuBar
        let template = theme.renderer == .cards && !appearance.statusColors
        HStack(spacing: 10) {
            ForEach(Array(Self.statuses.enumerated()), id: \.offset) { _, st in
                Renderers.renderer(for: theme)
                    .statusItem(StatusItemModel(status: st, appearance: appearance),
                                context: StatusItemContext(theme: theme, menuBarIsDark: true, template: template))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color(white: 0.12)))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
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
            Section("When the panel is taller than the screen") {
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
        case .servers: "server.rack"
        case .mac: "laptopcomputer"
        }
    }

    var color: Color {
        switch id {
        case .status: Color(red: 0.19, green: 0.82, blue: 0.35)
        case .seen: Color(red: 0.37, green: 0.36, blue: 0.90)
        case .attention: Color(red: 1, green: 0.62, blue: 0.04)
        case .applications: Color(red: 0.04, green: 0.52, blue: 1)
        case .servers: Color(red: 0.56, green: 0.56, blue: 0.58)
        case .mac: Color(red: 0.39, green: 0.82, blue: 1)
        }
    }

    @ViewBuilder var label: some View {
        switch id {
        case .status: RowLabel("Status", "The verdict, checks by health, observers live")
        case .seen: RowLabel("Seen from", "Which observers see a problem, and that the others don’t")
        case .attention: RowLabel("Needs attention", "Open incidents first, then anything else that needs a look")
        case .applications: RowLabel("Applications", "Services folded into the applications you declare")
        case .servers: RowLabel("Servers", "The Servers-tab card of each server you pin")
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
            ApplicationsMenu()
        case .servers:
            ServersButton()
        default:
            EmptyView()
        }
    }
}

/// Which applications the section shows: all, or those ticked.
struct ApplicationsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let known = model.knownApplications
        let only = model.settings.sections.applicationsOnly
        Menu {
            Button {
                model.update { $0.sections.applicationsOnly = [] }
            } label: {
                if only.isEmpty { Label("All", systemImage: "checkmark") } else { Text("All") }
            }
            if !known.isEmpty { Divider() }
            ForEach(known, id: \.id) { a in
                Button {
                    model.update { s in
                        var set = s.sections.applicationsOnly.isEmpty ? known.map(\.id) : s.sections.applicationsOnly
                        if let i = set.firstIndex(of: a.id) { set.remove(at: i) } else { set.append(a.id) }
                        s.sections.applicationsOnly = set.count == known.count ? [] : set
                    }
                } label: {
                    if only.isEmpty || only.contains(a.id) { Label(a.name, systemImage: "checkmark") } else { Text(a.name) }
                }
            }
        } label: {
            if only.isEmpty {
                Text(known.isEmpty ? String(localized: "All") : String(localized: "All \(known.count)"))
            } else {
                Text(known.isEmpty ? String(localized: "\(only.count) chosen") : String(localized: "\(only.count) of \(known.count)"))
            }
        }
        .fixedSize()
    }
}

/// The servers pinned, by node ID.
struct ServersButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button("Choose…") { open = true }
            .popover(isPresented: $open, arrowEdge: .bottom) { ServersPicker().environment(model) }
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
            reading(.cpu, "CPU", "Total, system and user, with a minute of history")
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

    var automatic: String {
        if let name = model.localInterfaceName { return String(localized: "Automatic (\(name))") }
        return String(localized: "Automatic")
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
                    Text(verbatim: s.id == suggestion?.id ? String(localized: "\(title) (matches this Mac)") : title).tag(s.id)
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
