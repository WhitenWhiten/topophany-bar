import Foundation
import LocalReadings
import TopophanyKit

/// The engine as the panel sees it.
public enum EngineCondition: Sendable, Hashable {
    case starting
    case running
    /// Ended; starts again at `at`.
    case restarting(at: Date?)
    case notFound
    case tooOld
    case stopped
}

/// What the panel is built from: what may be shown now, the engine, the
/// user's choices and this Mac's own readings.
public struct PanelInput: Sendable {
    public var reading: Reading
    public var engine: EngineCondition
    public var settings: Settings
    public var local: LocalSnapshot?
    public var machineModel: String

    public init(reading: Reading, engine: EngineCondition, settings: Settings, local: LocalSnapshot? = nil,
                machineModel: String = "Mac") {
        self.reading = reading
        self.engine = engine
        self.settings = settings
        self.local = local
        self.machineModel = machineModel
    }
}

/// Builds section models from frames. Every state, count and health here
/// was sent by `topo`; the builder only selects, orders and words them.
public enum SectionBuilder {
    public typealias RowID = TemplateCompiler.RowID

    public static func panel(_ input: PanelInput) -> PanelModel {
        let r = input.reading
        let s = input.settings.sections
        let status = status(r, engine: input.engine)
        var sections: [PanelModel.Section] = []
        for id in s.order {
            switch id {
            case .status:
                break
            case .seen where s.seen:
                sections.append(.seen(seen(r)))
            case .attention where s.attention:
                if let a = attention(r, limit: s.attentionLimit) { sections.append(.attention(a)) }
            case .applications where s.applications:
                if let a = applications(r, only: s.applicationsOnly) { sections.append(.applications(a)) }
            case .servers where s.servers:
                let cards = servers(r, nodes: s.serverNodes)
                if !cards.isEmpty { sections.append(.servers(cards)) }
            case .mac:
                switch s.mac.mode {
                case .off:
                    break
                case .local:
                    sections.append(.mac(.local(LocalSection(model: input.local?.machine.model ?? input.machineModel,
                                                             readings: s.mac.readings, snapshot: input.local))))
                case .server:
                    if let card = server(r, rowID: RowID.mac, node: s.mac.node) {
                        var c = card
                        if !s.mac.resources {
                            c.cpu = .init(percent: nil, limit: nil, detail: "")
                            c.memory = c.cpu
                            c.disk = c.cpu
                        }
                        if !s.mac.services { c.services = [] }
                        if !s.mac.observes { c.observes = [] }
                        sections.append(.mac(.server(c, node: s.mac.node)))
                    }
                }
            default:
                break
            }
        }
        return PanelModel(chrome: chrome(r, status: status, observer: input.settings.topo.observer),
                          status: status, sections: sections, pinStatus: s.pinStatus)
    }

    // MARK: status

    public static func status(_ r: Reading, engine: EngineCondition) -> StatusSection {
        let now = r.now
        func blind(_ b: StatusSection.Blind) -> StatusSection {
            StatusSection(kind: .blind(b), mark: .offline, updatedAt: r.frame?.generatedAt, lastKnown: r.lastKnown, now: now)
        }
        func engineBlind() -> StatusSection {
            switch engine {
            case .notFound: blind(.topoNotFound)
            case .tooOld: blind(.topoTooOld)
            case .restarting(let at): blind(.engineStopped(restartAt: at))
            case .stopped: blind(.engineStopped(restartAt: nil))
            case .starting, .running: blind(.starting)
            }
        }
        switch r.availability {
        case .waiting:
            return engineBlind()
        case .sourceEnded, .stopped:
            if case .starting = engine { return blind(.engineStopped(restartAt: nil)) }
            if case .running = engine { return blind(.engineStopped(restartAt: nil)) }
            return engineBlind()
        case .leaseExpired:
            return blind(.leaseLapsed)
        case .implausible, .unsupported:
            return blind(.unreadable)
        case .live:
            break
        }
        let barRow = r.frame?.barRow ?? ""
        guard let row = r.row(barRow.isEmpty ? RowID.status : barRow) ?? r.rows.first(where: { $0.row.metric == "summary.verdict" })
        else { return blind(.unknown(reason: "")) }
        switch row.status {
        case .current:
            guard case .verdict(let v) = row.value else { return blind(.unknown(reason: "")) }
            if v.state == .cached { return blind(.cached) }
            let mark: Mark
            switch v.state {
            case .clear: mark = .up
            case .degraded: mark = .degraded
            case .incidents, .down: mark = .down
            default: mark = .unknown
            }
            return StatusSection(kind: .verdict(v.state), mark: mark, topoText: v.text, counts: v.counts?.health,
                                 paused: v.counts?.paused, maintenance: v.counts?.maintenance, configured: v.configured,
                                 incidents: v.incidents, observersLive: v.observers?.live, observersAll: v.observers?.all,
                                 updatedAt: r.frame?.generatedAt, lastKnown: r.lastKnown, now: now)
        case .withheld(.noValue):
            switch row.row.reason {
            case "source_unavailable": return blind(.collectorUnreachable)
            case "source_expired": return blind(.snapshotExpired)
            default: return blind(.unknown(reason: row.row.reason))
            }
        case .withheld(.expired):
            return blind(.verdictExpired)
        case .withheld(.implausible):
            return blind(.unreadable)
        case .withheld(.unavailable):
            return blind(.leaseLapsed)
        }
    }

    // MARK: seen from

    public static func seen(_ r: Reading) -> SeenFromSection {
        guard let row = r.row(RowID.seen) else { return SeenFromSection(problems: nil, calm: 0, total: nil) }
        guard case .observers(let list) = row.value else {
            if case .observers(let last) = r.lastValue(of: row) { return SeenFromSection(problems: nil, calm: 0, total: last.count) }
            return SeenFromSection(problems: nil, calm: 0, total: nil)
        }
        let problems = list.filter { $0.health != .up }.map { o in
            SeenFromSection.Entry(id: o.id, name: o.name, mark: Mark(o.health), note: note(o, now: r.now))
        }
        return SeenFromSection(problems: problems, calm: list.count { $0.health == .up }, total: list.count)
    }

    /// "3 down", "1 warn", "silent 3m", "7 unknown".
    static func note(_ o: ObserverVerdict, now: Date) -> String {
        if let d = o.counts?.down, d > 0 { return tr("\(d) down") }
        if let w = o.counts?.warning, w > 0 { return tr("\(w) warn") }
        if o.live == false {
            return o.lastSeen.map { tr("silent \(Words.span(since: $0, now: now, style: .compact))") } ?? tr("silent")
        }
        if let u = o.counts?.unknown, u > 0 { return tr("\(u) unknown") }
        return Mark(o.health).word
    }

    // MARK: needs attention

    /// `nil` when there is nothing to show: empty, or not current.
    public static func attention(_ r: Reading, limit: Int) -> AttentionSection? {
        guard let row = r.row(RowID.attention), case .attention(let list) = row.value else { return nil }
        let items = list.items.prefix(max(1, limit)).map { a in
            AttentionSection.Item(id: a.id, kind: a.kind, route: a.route, mark: Mark(a.health),
                                  pill: Pill.state(a.state, health: a.health), observer: a.observer,
                                  observerName: a.observerName, since: a.since)
        }
        let total = max(list.total ?? list.items.count, items.count)
        guard !items.isEmpty || total > 0 else { return nil }
        return AttentionSection(items: Array(items), total: total, now: r.now)
    }

    // MARK: applications

    public static func applications(_ r: Reading, only: [String]) -> ApplicationsSection? {
        guard let row = r.row(RowID.applications) else { return nil }
        let current: Bool
        let list: [Application]
        if case .applications(let l) = row.value {
            current = true
            list = l
        } else if case .applications(let l) = r.lastValue(of: row) {
            current = false
            list = l
        } else {
            return nil
        }
        let shown = only.isEmpty ? list : list.filter { only.contains($0.id) }
        let rows = shown.map { a -> ApplicationsSection.Row in
            guard current else {
                return .init(id: a.id, name: a.name, mark: .offline, services: a.services.map { _ in .offline },
                             note: tr("cached"), noteNeedsLook: false)
            }
            let services = a.services.map { s -> Mark in s.monitored == false ? .unknown : Mark(s.health) }
            let (note, look) = applicationNote(a)
            return .init(id: a.id, name: a.name, mark: Mark(a.health), services: services, note: note, noteNeedsLook: look)
        }
        return ApplicationsSection(rows: rows, isCurrent: current)
    }

    static func applicationNote(_ a: Application) -> (String, Bool) {
        let attention = a.attention ?? 0
        let unmonitored = a.unmonitored ?? 0
        let unknown = max(0, (a.counts?.unknown ?? 0) - unmonitored)
        let problems = (a.counts?.warning ?? 0) + (a.counts?.down ?? 0)
        if problems > 0 || a.health == .degraded || a.health == .down {
            return (tr("\(max(attention, problems)) attention"), true)
        }
        if unknown > 0 { return (tr("\(unknown) unknown"), false) }
        if unmonitored > 0 { return (tr("\(unmonitored) not monitored"), false) }
        if a.health == .up { return (tr("all up"), false) }
        return (Mark(a.health).word, false)
    }

    // MARK: servers

    public static func servers(_ r: Reading, nodes: [String]) -> [ServerCardModel] {
        var out: [ServerCardModel] = []
        var seen = Set<String>()
        for node in nodes where TemplateCompiler.validNode(node) && seen.insert(node).inserted {
            let row = r.rows.first { $0.row.metric == "server.card" && $0.row.select?.node == node && $0.row.id != RowID.mac }
            if let c = server(row, node: node, reading: r) { out.append(c) }
        }
        return out
    }

    static func server(_ r: Reading, rowID: String, node: String) -> ServerCardModel? {
        server(r.row(rowID), node: node, reading: r)
    }

    static func server(_ row: RowReading?, node: String, reading r: Reading) -> ServerCardModel? {
        guard let row else { return nil }
        let now = r.now
        if case .serverCard(let c) = row.value { return card(c, withheld: false, now: now) }
        if case .serverCard(let c) = r.lastValue(of: row) { return card(c, withheld: true, now: now) }
        let missing = row.row.reason == "entity_missing"
        let none = ServerCardModel.Meter(percent: nil, limit: nil, detail: "")
        return ServerCardModel(id: node, name: node, kind: "", provider: "", place: missing ? tr("Not in the topology") : "",
                               mark: missing ? .unknown : .offline, pill: missing ? Pill.health(.unknown) : .cached,
                               isWithheld: !missing, isMissing: missing, cpu: none, memory: none, disk: none, services: [],
                               servicesSummary: "", observes: [], sampledAt: nil, now: now)
    }

    static func card(_ c: ServerCard, withheld: Bool, now: Date) -> ServerCardModel {
        let res = c.resources.first
        func size(_ used: Int64?, _ total: Int64?) -> String {
            guard let used, let total else { return "" }
            return tr("\(Words.gib(used)) / \(Words.gib(total)) GiB")
        }
        let cpu = ServerCardModel.Meter(percent: withheld ? nil : res?.cpu?.percent, limit: res?.cpu?.limit,
                                        detail: res?.cpu?.logical.map { tr("\($0) CPUs") } ?? "")
        let memory = ServerCardModel.Meter(percent: withheld ? nil : res?.memory?.percent, limit: res?.memory?.limit,
                                           detail: withheld ? "" : size(res?.memory?.usedBytes, res?.memory?.totalBytes))
        let disk = ServerCardModel.Meter(percent: withheld ? nil : res?.disk?.percent, limit: res?.disk?.limit,
                                         detail: withheld ? "" : size(res?.disk?.usedBytes, res?.disk?.totalBytes))
        let services = c.services.map { s in
            ServerCardModel.Service(
                id: s.id, name: s.name, mark: withheld ? .offline : (s.monitored == false ? .unknown : Mark(s.health)),
                note: withheld ? "" : s.affected == true ? tr("affected") : s.monitored == false ? tr("not monitored") : "")
        }
        let observes = c.observes.map { o in
            ServerCardModel.Observes(id: o.id, name: o.name, mark: withheld ? .offline : Mark(o.health),
                                     text: withheld ? tr("not known while offline") : observesText(o))
        }
        let pill: Pill
        if withheld {
            pill = .cached
        } else if c.note.isEmpty {
            pill = Pill.health(c.health)
        } else {
            pill = Pill.state(c.note, health: c.health)
        }
        return ServerCardModel(id: c.id, name: c.name, kind: c.kind, provider: c.provider, place: c.place,
                               mark: withheld ? .offline : Mark(c.health), pill: pill, isWithheld: withheld,
                               cpu: cpu, memory: memory, disk: disk, services: services,
                               servicesSummary: servicesSummary(c.services), observes: observes,
                               sampledAt: res?.sampledAt, now: now)
    }

    /// "4 services · 3 up · 1 not monitored".
    static func servicesSummary(_ s: [ServiceEntry]) -> String {
        guard !s.isEmpty else { return tr("no services") }
        let monitored = s.filter { $0.monitored != false }
        let up = monitored.count { $0.health == .up && $0.affected != true }
        let attention = monitored.count { $0.health == .down || $0.health == .degraded || $0.affected == true }
        let unknown = monitored.count { $0.health == .unknown }
        let unmonitored = s.count - monitored.count
        if up == s.count { return Words.join([tr("\(s.count) services"), tr("all up")]) }
        return Words.join([
            tr("\(s.count) services"),
            up > 0 ? tr("\(up) up") : "",
            attention > 0 ? tr("\(attention) attention") : "",
            unknown > 0 ? tr("\(unknown) unknown") : "",
            unmonitored > 0 ? tr("\(unmonitored) not monitored") : "",
        ])
    }

    /// "9 checks · all pass", "14 checks · 1 down".
    static func observesText(_ o: ObserverVerdict) -> String {
        guard let c = o.counts?.complete else { return Mark(o.health).word }
        let n = c.up + c.warning + c.down + c.unknown
        if o.live == false { return Words.join([tr("\(n) checks"), tr("not live")]) }
        if c.down > 0 { return Words.join([tr("\(n) checks"), tr("\(c.down) down")]) }
        if c.warning > 0 { return Words.join([tr("\(n) checks"), tr("\(c.warning) warn")]) }
        if c.unknown > 0 { return Words.join([tr("\(n) checks"), tr("\(c.unknown) unknown")]) }
        return Words.join([tr("\(n) checks"), tr("all pass")])
    }

    // MARK: chrome

    static func chrome(_ r: Reading, status: StatusSection, observer: String) -> PanelChrome {
        let connection: PanelChrome.Connection
        switch status.kind {
        case .verdict: connection = .connected
        case .blind(.starting): connection = .starting
        case .blind(.engineStopped(let at)): connection = .restarting(at: at)
        case .blind(.topoNotFound): connection = .notRunning(tr("topo not found"))
        case .blind(.topoTooOld): connection = .notRunning(tr("topo needs an upgrade"))
        case .blind(.leaseLapsed): connection = .notRunning(tr("topo stopped answering"))
        case .blind: connection = .unreachable
        }
        var view = tr("all observers")
        if !observer.isEmpty {
            view = observer
            if let row = r.row(RowID.seen), case .observers(let list) = row.row.value,
               let o = list.first(where: { $0.id == observer }) {
                view = o.name
            }
        }
        return PanelChrome(project: r.frame?.project ?? "", view: view, connection: connection,
                           updatedAt: r.frame?.generatedAt, now: r.now)
    }
}
