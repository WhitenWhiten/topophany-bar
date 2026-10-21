import AppKit
import LocalReadings
import Observation
import TopophanyEngine
import TopophanyKit
import TopophanySections
import TopophanyThemes
import TopophanyWidgets

/// The app's one source of truth. Frames flow one way: the engine writes
/// them, the reader policy says what may be shown at this second, the
/// section builder words it, and the renderers draw it.
@MainActor
@Observable
final class AppModel {
    private(set) var settings: TopophanyKit.Settings
    private(set) var panel: PanelModel
    private(set) var status: StatusSection
    private(set) var statusItem: StatusItemModel
    private(set) var reading: Reading
    private(set) var engineStatus: EngineStatus = .starting
    private(set) var diagnostics: [String] = []
    private(set) var capabilities: Capabilities?
    /// Saved profiles, when `topo` lists them.
    private(set) var profiles: ProfileList?
    private(set) var lastFrameAt: Date?
    /// The keyboard's place in the panel.
    var focus: String?
    /// Space presses in the panel, each a leap of its quick scroll.
    var leaps = 0
    /// The menu bar's alert, quieted until it gets worse. Kept for this
    /// launch only.
    private(set) var quiet: QuietAlert?

    let themes = ThemeStore()
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private var policy = ReaderPolicy()
    @ObservationIgnored private var engine: (any Engine)?
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    @ObservationIgnored private var restartAt: Date?
    @ObservationIgnored private var local: LocalSnapshot?
    @ObservationIgnored private var localTask: Task<Void, Never>?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var widgetNeeds = TemplateCompiler.WidgetNeeds.none
    @ObservationIgnored private var panelVisible = false
    @ObservationIgnored private var settingsVisible = false
    @ObservationIgnored private var locateTask: Task<Void, Never>?
    @ObservationIgnored private var profilesTask: Task<Void, Never>?
    @ObservationIgnored private var profilesRevision = 0
    @ObservationIgnored let machine = MachineInfo.current()
    /// Replays a fixture instead of running `topo`, for development:
    /// `-fixture incidents`.
    @ObservationIgnored private(set) var fixture = UserDefaults.standard.string(forKey: "fixture")
        .flatMap(FixtureEngine.Scenario.init(rawValue:))
    /// Reads `topo`'s synthetic preview network for this launch, without
    /// saving it: `-preview 1` for scenario 1.
    @ObservationIgnored let previewScenario: Int? = UserDefaults.standard.object(forKey: "preview") != nil
        ? max(0, UserDefaults.standard.integer(forKey: "preview")) : nil
    /// Runs another `topo` for this launch, without saving it: `-topo PATH`.
    @ObservationIgnored let topoOverride = UserDefaults.standard.string(forKey: "topo")
    /// Where `topo` was found, for Settings.
    private(set) var located: Result<TopoLocator.Found, EngineProblem>?
    /// Every `topo` on this Mac, checked, for Settings to choose from.
    private(set) var candidates: [TopoCandidate] = []
    /// The copies the app downloaded, newest first.
    private(set) var downloaded: [TopoDownloads.Installed] = []
    /// Getting `topo` from its releases.
    private(set) var fetch: TopoFetch = .idle
    /// Where downloaded copies go: beside the settings file.
    @ObservationIgnored let downloads: TopoDownloads
    @ObservationIgnored let iconLibrary: MenuBarIconLibrary
    private(set) var customIcons: [MenuBarIconAsset] = []
    private(set) var customIconAnimation: MenuBarIconAnimation?
    private(set) var iconError: String?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var widgets: WidgetBridge?

    /// Debug builds take `-settings PATH` to use another settings file.
    static var defaultStore: SettingsStore {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "settings") {
            return SettingsStore(url: URL(filePath: (path as NSString).expandingTildeInPath))
        }
        #endif
        return SettingsStore()
    }

    /// Told when a saved setting changes, before `topo` hears of it.
    @ObservationIgnored var onSettingsChange: ((_ old: TopophanyKit.Settings, _ new: TopophanyKit.Settings) -> Void)?

    init(store: SettingsStore = AppModel.defaultStore) {
        self.store = store
        downloads = TopoDownloads(besideSettings: store.url)
        iconLibrary = MenuBarIconLibrary(directory: store.url.deletingLastPathComponent().appending(path: "MenuBarIcons"))
        let s = store.load()
        L10n.prefer(s.language.localization)
        settings = s
        let r = ReaderPolicy().evaluate(at: Date())
        reading = r
        let p = SectionBuilder.panel(PanelInput(reading: r, engine: .starting, settings: s))
        panel = p
        status = p.status
        statusItem = StatusItemModel(status: p.status, appearance: s.appearance.menuBar, local: nil)
        reloadIcons()
    }

    var theme: Theme { themes.theme(settings.appearance.theme) }

    /// The settings as this launch runs them: a `-preview` launch reads the
    /// synthetic network whatever is saved.
    var effectiveSettings: TopophanyKit.Settings { effective(settings) }

    private func effective(_ s: TopophanyKit.Settings) -> TopophanyKit.Settings {
        var e = s
        if let topoOverride { e.topo.path = topoOverride }
        if let previewScenario {
            e.topo.source = "preview"
            e.topo.scenario = previewScenario
        }
        return e
    }

    /// Observers by ID and name, from the latest list `topo` sent.
    var knownObservers: [(id: String, name: String)] {
        guard let row = reading.row(TemplateCompiler.RowID.seen),
              case .observers(let list) = reading.lastValue(of: row) else { return [] }
        return list.map { ($0.id, $0.name) }
    }

    /// Nodes with a card in the Servers tab, from the latest list `topo`
    /// sent, for choosing nodes.
    var knownServers: [ServerListEntry] {
        guard let row = reading.row(TemplateCompiler.RowID.servers),
              case .servers(let list) = reading.lastValue(of: row) else { return [] }
        return list
    }

    /// The places `topo` names for its servers, in its order, with how many
    /// servers each has; then places given a zone that it no longer names.
    var knownPlaces: [(place: String, servers: Int)] {
        let listed = knownServers.isEmpty
            ? SectionBuilder.servers(reading, nodes: settings.sections.serverNodes).filter { !$0.isMissing }.map(\.place)
            : knownServers.map(\.place)
        var out: [(place: String, servers: Int)] = []
        for p in listed where !p.isEmpty {
            if let i = out.firstIndex(where: { $0.place == p }) { out[i].servers += 1 } else { out.append((p, 1)) }
        }
        for p in settings.sections.placeZones.keys.sorted() where !out.contains(where: { $0.place == p }) { out.append((p, 0)) }
        return out
    }

    /// Whether to ask for pinned services' cards: when this `topo` offers
    /// `service.card`. An older one draws everything else.
    var cardsServices: Bool { fixture != nil || (capabilities?.cardsServices ?? true) }

    /// Whether to ask for `map.graph`: when this `topo` draws a map.
    /// Without it, the map places servers by name.
    var mapGraph: Bool { fixture != nil || (capabilities?.drawsMap ?? true) }

    /// Services with a card, from the latest list `topo` sent, for choosing
    /// services; without one, the services the applications list.
    var knownServices: [ServiceListEntry] {
        if let row = reading.row(TemplateCompiler.RowID.services), case .services(let list) = reading.lastValue(of: row) {
            return list
        }
        return knownApplications.flatMap { a in
            a.services.map { ServiceListEntry(id: $0.id, name: $0.name, application: a.name, health: $0.health, monitored: $0.monitored) }
        }
    }

    /// The applications in the latest list `topo` sent.
    var knownApplications: [Application] {
        guard let row = reading.row(TemplateCompiler.RowID.applications),
              case .applications(let list) = reading.lastValue(of: row) else { return [] }
        return list
    }

    /// The interface local readings measure when none is chosen.
    var localInterfaceName: String? { local?.latest.network?.displayName }

    /// Looks for `topo` again, every copy of it, and lists its profiles
    /// again, off the main thread.
    func locate() {
        guard locateTask == nil else { return }
        let path = effectiveSettings.topo.path
        let refreshProfiles = engineStatus.isRunning
        let downloads = self.downloads
        locateTask = Task { [weak self] in
            let (found, installed, all) = await Task.detached {
                // One shell for both phases of this scan.
                let shellPath = TopoLocator.loginShellPATH()
                let locator = TopoLocator(setting: path, shellPath: { shellPath }, downloads: downloads)
                return (locator.locate(), downloads.installed(), locator.candidates())
            }.value
            guard let self else { return }
            self.locateTask = nil
            guard self.effectiveSettings.topo.path == path else { self.locate(); return }
            self.located = found
            self.downloaded = installed
            self.candidates = all
            if refreshProfiles, case .running(let r) = self.engineStatus, self.fixture == nil, self.capabilities?.profiles == true {
                self.loadProfiles(path: r.path)
            }
        }
    }

    // MARK: getting topo

    /// Downloads `topo` and runs it: the latest release, or the one this
    /// app was tested with. Nothing reaches the network until this is asked.
    func download(_ build: TopoBuild) {
        guard !fetch.isDownloading else { return }
        fetch = .downloading(build, version: build == .tested ? TopoRelease.tested.version : nil, fraction: nil)
        refresh()
        let downloads = self.downloads
        Task {
            do {
                let release = build == .tested ? TopoRelease.tested : try await TopoRelease.latest()
                fetch = .downloading(build, version: release.version, fraction: nil)
                refresh()
                let installed = try await downloads.install(release) { f in
                    Task { @MainActor in
                        guard case .downloading(build, let v, _) = self.fetch else { return }
                        self.fetch = .downloading(build, version: v, fraction: f)
                        self.refresh()
                    }
                }
                fetch = .idle
                use(installed.path)
            } catch {
                let problem = error as? TopoFetchProblem ?? .unreachable(error.localizedDescription)
                // The latest couldn't be used: offer the tested release instead.
                var next = build
                if case .unusable = problem { next = .tested }
                fetch = .failed(next: next, problem)
                diagnostics.append("download: \(problem)")
                refresh()
            }
        }
    }

    /// Runs the `topo` at `path`, or searches again when it's empty.
    func use(_ path: String) {
        if settings.topo.path == path {
            restartEngine()
            locate()
        } else {
            update { $0.topo.path = path }
        }
    }

    /// Deletes a downloaded copy. When it's the one running, or chosen, the
    /// app searches again, and says so if it finds none.
    func deleteDownload(_ installed: TopoDownloads.Installed) {
        let running = if case .running(let r) = engineStatus { r.path } else { "" }
        try? downloads.delete(installed)
        if settings.topo.path == installed.path {
            update { $0.topo.path = "" }
        } else if running == installed.path {
            restartEngine()
        }
        locate()
    }

    private func loadProfiles(path: String) {
        guard profilesTask == nil else { return }
        profilesRevision += 1
        let revision = profilesRevision
        profilesTask = Task { [weak self] in
            let list = await Task.detached { ProcessEngine.profiles(path) }.value
            guard let self, self.profilesRevision == revision else { return }
            self.profilesTask = nil
            guard !Task.isCancelled, case .running(let r) = self.engineStatus, r.path == path else { return }
            let signedIn = self.profiles?.profiles.isEmpty == true && list?.profiles.isEmpty == false
            self.profiles = list
            if signedIn { self.restartEngine() }
        }
    }

    // MARK: running

    func start() {
        if fixture != nil { profiles = FixtureEngine.profiles }
        locate()
        startEngine()
        startLocal()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
        refresh()
    }

    /// Closes `topo`'s stdin at once; it writes its last frame and exits.
    func stopNow() {
        (engine as? ProcessEngine)?.closeInputNow()
        localTask?.cancel()
    }

    func update(_ change: (inout TopophanyKit.Settings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        let old = settings
        L10n.prefer(s.language.localization)
        settings = s
        if old.appearance.menuBar.customIconID != s.appearance.menuBar.customIconID || old.appearance.menuBar.icon != s.appearance.menuBar.icon {
            reloadIcons()
        }
        try? store.save(s)
        onSettingsChange?(old, s)
        if old.topo.path != s.topo.path || old.topo.source != s.topo.source {
            restartEngine()
            locate()
        } else if request(old) != request(s) || old.language != s.language {
            // `topo preview` names its network in the panel's language.
            send()
        }
        if old.sections.mac != s.sections.mac || old.sections.order != s.sections.order
            || old.appearance.menuBar.readings != s.appearance.menuBar.readings {
            startLocal()
        }
        refresh()
    }

    func reloadIcons() {
        customIcons = iconLibrary.list()
        customIconAnimation = nil
        iconError = nil
        if settings.appearance.menuBar.icon == .custom, let id = settings.appearance.menuBar.customIconID {
            do { customIconAnimation = try iconLibrary.load(id) }
            catch { iconError = tr("This custom icon is unavailable. The default icon is shown instead.") }
        }
    }

    func selectIcon(_ selection: String) {
        update { settings in
            if let icon = Settings.Appearance.MenuBar.Icon(rawValue: selection), icon != .custom {
                settings.appearance.menuBar.icon = icon
            } else {
                settings.appearance.menuBar.icon = .custom
                settings.appearance.menuBar.customIconID = selection
            }
        }
    }

    func removeIcon(_ id: String) throws {
        try iconLibrary.remove(id)
        if settings.appearance.menuBar.customIconID == id {
            update { $0.appearance.menuBar.icon = .globe; $0.appearance.menuBar.customIconID = nil }
        }
        reloadIcons()
    }

    func setWidgetNeeds(_ needs: TemplateCompiler.WidgetNeeds) {
        guard needs != widgetNeeds else { return }
        widgetNeeds = needs
        send()
    }

    private func request(_ s: TopophanyKit.Settings) -> Request {
        var r = TemplateCompiler().request(for: effective(s), revision: 0, widgets: widgetNeeds, lang: L10n.previewLanguage,
                                           listServers: true, serviceCards: true, listServices: true, mapGraph: true)
        r.requestID = ""
        return r
    }

    private func currentRequest() -> Request {
        revision += 1
        return TemplateCompiler().request(for: effectiveSettings, revision: revision, widgets: widgetNeeds,
                                          lang: L10n.previewLanguage, listServers: true, serviceCards: true,
                                          listServices: true, mapGraph: true)
    }

    private func send() {
        guard let engine else { return }
        let r = currentRequest()
        Task { try? await engine.update(r) }
    }

    #if DEBUG
    /// Replays another fixture from its start, as if `topo` had moved on.
    func replay(_ scenario: FixtureEngine.Scenario) {
        guard fixture != nil else { return }
        fixture = scenario
        restartEngine()
    }
    #endif

    func restartEngine() {
        let old = engine
        engineTask?.cancel()
        engine = nil
        if let p = old as? ProcessEngine { p.closeInputNow() }
        Task { await old?.stop() }
        policy.sourceEnded(at: Date())
        startEngine()
    }

    private func startEngine() {
        engineStatus = .starting
        capabilities = nil
        profilesRevision += 1
        profilesTask?.cancel()
        profilesTask = nil
        let e: any Engine
        if let fixture {
            e = FixtureEngine(scenario: fixture)
        } else {
            e = ProcessEngine(configuration: .init(topoPath: effectiveSettings.topo.path, downloads: downloads))
        }
        engine = e
        let stream = e.start(currentRequest())
        engineTask = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    func handle(_ event: EngineEvent) {
        let now = Date()
        switch event {
        case .frame(let f, let line):
            policy.receive(f, line: line, at: now)
            if f.lifecycle == .running { lastFrameAt = now }
        case .status(let s):
            engineStatus = s
            switch s {
            case .running:
                policy.sourceStarted()
                restartAt = nil
                if case .running(let r) = s, fixture == nil, capabilities?.profiles == true { loadProfiles(path: r.path) }
            case .restarting(let after, _, _):
                policy.sourceEnded(at: now)
                restartAt = now.addingTimeInterval(after)
            case .unavailable, .stopped:
                policy.sourceEnded(at: now)
                restartAt = nil
            case .starting:
                break
            }
        case .diagnostic(let d):
            appendDiagnostics([d])
            return
        case .diagnostics(let pending):
            appendDiagnostics(pending.drain())
            return
        case .sourceEnded:
            policy.sourceEnded(at: now)
        case .capabilities(let caps):
            capabilities = caps
            if !caps.profiles { profiles = nil }
            return
        }
        refresh()
    }

    private func appendDiagnostics(_ lines: [String]) {
        diagnostics.append(contentsOf: lines)
        if diagnostics.count > 50 { diagnostics.removeFirst(diagnostics.count - 50) }
    }

    var engineCondition: EngineCondition {
        switch engineStatus {
        case .starting: .starting
        case .running: .running
        case .restarting: .restarting(at: restartAt)
        case .unavailable(.notFound): .notFound
        case .unavailable(.upgradeNeeded), .unavailable(.unsupported): .tooOld
        case .unavailable(.launchFailed): .stopped
        case .stopped: .stopped
        }
    }

    // MARK: this Mac

    /// Samples what This Mac's card and the menu bar item show between
    /// them, and nothing while neither shows a reading.
    private func startLocal() {
        localTask?.cancel()
        local = nil
        let mac = settings.sections.mac
        var kinds = Set<LocalReadingKind>()
        if mac.mode == .local, settings.sections.isEnabled(.mac) {
            for r in mac.readings {
                switch r {
                case .cpu: kinds.insert(.cpu)
                case .memory: kinds.insert(.memory)
                case .storage: kinds.insert(.storage)
                case .network: kinds.insert(.network)
                case .battery: kinds.insert(.battery)
                }
            }
        }
        for r in settings.appearance.menuBar.readings {
            switch r {
            case .cpu: kinds.insert(.cpu)
            case .memory: kinds.insert(.memory)
            case .network: kinds.insert(.network)
            }
        }
        guard !kinds.isEmpty else { return }
        let monitor = LocalReadingsMonitor(configuration: .init(
            kinds: kinds, every: Interval(mac.every)?.seconds ?? 2, volumePath: mac.volume, interface: mac.interface))
        localTask = Task { [weak self] in
            for await snap in monitor.snapshots() {
                guard let self, !Task.isCancelled else { return }
                self.local = snap
                self.refresh()
            }
        }
    }

    // MARK: every second

    /// Quiets the menu bar's alert until it gets worse, or shows it again.
    func toggleQuiet() {
        switch menuBarAlert {
        case .shown: quiet = QuietAlert(status)
        case .quiet: quiet = nil
        case .unavailable: return
        }
        refresh()
    }

    var menuBarAlert: MenuBarAlert {
        !settings.appearance.menuBar.statusColors || !QuietAlert.alerts(status) ? .unavailable : quiet == nil ? .shown : .quiet
    }

    func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        if visible { refresh() }
    }

    func setSettingsVisible(_ visible: Bool) {
        guard settingsVisible != visible else { return }
        settingsVisible = visible
        if visible { refresh() }
    }

    func refresh(at now: Date = Date()) {
        let r = policy.evaluate(at: now)
        reading = r
        let status = SectionBuilder.status(r, engine: engineCondition)
        self.status = status
        quiet = quiet?.after(status)
        let visible = panelVisible || settingsVisible
        if visible {
            panel = SectionBuilder.panel(PanelInput(reading: r, engine: engineCondition, settings: settings, local: local,
                                                    machineModel: machine.model, quiet: quiet, fetch: fetch))
        }
        let item = StatusItemModel(status: status, appearance: settings.appearance.menuBar, local: local, quiet: quiet)
        if item != statusItem { statusItem = item }
        widgets?.tick(panel: visible ? panel : nil, status: status, reading: r, policy: policy, theme: theme, settings: settings, at: now)
        onChange?()
    }
}
