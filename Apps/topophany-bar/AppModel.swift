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
        let s = store.load()
        L10n.prefer(s.language.localization)
        settings = s
        let r = ReaderPolicy().evaluate(at: Date())
        reading = r
        let p = SectionBuilder.panel(PanelInput(reading: r, engine: .starting, settings: s))
        panel = p
        statusItem = StatusItemModel(status: p.status, appearance: s.appearance.menuBar, local: nil)
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
        let listed = knownServers.isEmpty ? panel.servers.filter { !$0.isMissing }.map(\.place) : knownServers.map(\.place)
        var out: [(place: String, servers: Int)] = []
        for p in listed where !p.isEmpty {
            if let i = out.firstIndex(where: { $0.place == p }) { out[i].servers += 1 } else { out.append((p, 1)) }
        }
        for p in settings.sections.placeZones.keys.sorted() where !out.contains(where: { $0.place == p }) { out.append((p, 0)) }
        return out
    }

    /// Whether to ask for `servers.list`: when this `topo` offers it.
    private var listServers: Bool { fixture != nil || capabilities?.listsServers == true }

    /// Applications by ID and name, from the latest list `topo` sent.
    var knownApplications: [(id: String, name: String)] {
        guard let row = reading.row(TemplateCompiler.RowID.applications),
              case .applications(let list) = reading.lastValue(of: row) else { return [] }
        return list.map { ($0.id, $0.name) }
    }

    /// The interface local readings measure when none is chosen.
    var localInterfaceName: String? { local?.latest.network?.displayName }

    /// Looks for `topo` again, and lists its profiles again, off the main
    /// thread.
    func locate() {
        let setting = effectiveSettings.topo.path
        Task.detached {
            let r = TopoLocator(setting: setting).locate()
            await MainActor.run { self.located = r }
        }
        if case .running(let r) = engineStatus, fixture == nil, capabilities?.profiles == true { loadProfiles(path: r.path) }
    }

    private func loadProfiles(path: String) {
        Task.detached {
            let list = ProcessEngine.profiles(path)
            await MainActor.run { self.profiles = list }
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

    func setWidgetNeeds(_ needs: TemplateCompiler.WidgetNeeds) {
        guard needs != widgetNeeds else { return }
        widgetNeeds = needs
        send()
    }

    private func request(_ s: TopophanyKit.Settings) -> Request {
        var r = TemplateCompiler().request(for: effective(s), revision: 0, widgets: widgetNeeds, lang: L10n.previewLanguage,
                                           listServers: listServers)
        r.requestID = ""
        return r
    }

    private func currentRequest() -> Request {
        revision += 1
        return TemplateCompiler().request(for: effectiveSettings, revision: revision, widgets: widgetNeeds,
                                          lang: L10n.previewLanguage, listServers: listServers)
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
        let e: any Engine
        if let fixture {
            e = FixtureEngine(scenario: fixture)
        } else {
            e = ProcessEngine(configuration: .init(topoPath: effectiveSettings.topo.path))
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

    private func handle(_ event: EngineEvent) {
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
                if case .running(let r) = s, fixture == nil { loadCapabilities(path: r.path) }
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
            diagnostics.append(d)
            if diagnostics.count > 50 { diagnostics.removeFirst(diagnostics.count - 50) }
        }
        refresh()
    }

    private func loadCapabilities(path: String) {
        Task.detached {
            let caps = try? ProcessEngine.check(path).get()
            await MainActor.run {
                let listed = self.listServers
                self.capabilities = caps
                if self.listServers != listed { self.send() }
                if caps?.profiles == true { self.loadProfiles(path: path) } else { self.profiles = nil }
            }
        }
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
        switch panel.alert {
        case .shown: quiet = QuietAlert(panel.status)
        case .quiet: quiet = nil
        case .unavailable: return
        }
        refresh()
    }

    func refresh() {
        let r = policy.evaluate(at: Date())
        reading = r
        quiet = quiet?.after(SectionBuilder.status(r, engine: engineCondition))
        panel = SectionBuilder.panel(PanelInput(reading: r, engine: engineCondition, settings: settings, local: local,
                                                machineModel: machine.model, quiet: quiet))
        let item = StatusItemModel(status: panel.status, appearance: settings.appearance.menuBar, local: local, quiet: quiet)
        if item != statusItem { statusItem = item }
        widgets?.tick(panel: panel, policy: policy, theme: theme, settings: settings)
        onChange?()
    }
}
