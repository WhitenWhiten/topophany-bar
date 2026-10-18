import Foundation
import Testing
@testable import TopophanySections
import TopophanyEngine
import TopophanyKit

let origin = Timestamp.parse("2027-03-01T09:00:00Z")!

func settings(limit: Int = 3, servers: Bool = true, mac: Sections.MacMode = .server) -> Settings {
    var s = Settings()
    s.sections.attentionLimit = limit
    s.sections.servers = servers
    s.sections.serverNodes = ["oracle-ny", "bwh-la"]
    s.sections.mac.mode = mac
    s.sections.mac.node = "macbook"
    return s
}

func panel(_ scenario: FixtureEngine.Scenario, after: TimeInterval = 4, settings s: Settings = settings(),
           engine: EngineCondition = .running) -> PanelModel {
    let request = TemplateCompiler().request(for: s, revision: 1)
    let reading = FixtureEngine.reading(scenario, request: request, origin: origin, after: after)
    return SectionBuilder.panel(PanelInput(reading: reading, engine: engine, settings: s))
}

@Suite struct SectionBuilderTests {
    init() { L10n.force("en") }

    @Test func clear() {
        let p = panel(.clear)
        #expect(p.status.mark == .up)
        #expect(p.status.title == "All clear")
        #expect(p.status.subtitle == "68 of 68 checks passing")
        #expect(p.status.count == nil)
        #expect(p.status.big.digits == "68")
        #expect(p.status.tuiTitle == "ALL CLEAR")
        #expect(p.chrome.isLive)
        #expect(p.chrome.project == "homelab")
        #expect(p.chrome.view == "all observers")
        #expect(p.chrome.connectionText == "Connected · homelab")
        #expect(p.seen?.problems == [])
        #expect(p.seen?.calm == 11)
        #expect(p.attention == nil, "hidden when empty")
        #expect(p.sections.map(\.id) == [.seen, .applications, .servers, .mac])
        let apps = p.applications!
        #expect(apps.rows.map(\.name) == ["Proxy chain", "Code & backups", "Main site", "Personal cloud", "Remote access", "Serverless"])
        #expect(apps.serviceCount == 23)
        #expect(apps.rows[0].note == "all up")
        // An unmonitored service leaves the group unknown, as topo says.
        #expect(apps.rows[1].mark == .unknown)
        #expect(apps.rows[1].services == [.up, .up, .unknown])
        #expect(apps.rows[1].note == "1 not monitored")
    }

    @Test func degraded() {
        let p = panel(.degraded)
        #expect(p.status.mark == .degraded)
        #expect(p.status.subtitle == "2 checks warning · no incidents")
        #expect(p.status.count == 2)
        #expect(p.seen?.problems?.map(\.name) == ["Seattle MacBook", "Seattle Windows"])
        #expect(p.seen?.problems?.map(\.note) == ["1 warn", "1 warn"])
        #expect(p.seen?.calm == 9)
        let a = p.attention!
        #expect(a.items.map(\.title) == ["VLESS+Reality Entry (Primary)", "Exit Candidates (BandwagonHost · Azure)"])
        #expect(a.items.map(\.pill.text) == ["WARN", "WARN"])
        #expect(a.items[0].since == nil)
        #expect(a.more == 0)
        #expect(p.applications?.rows[0].note == "2 attention")
        #expect(p.applications?.rows[0].noteNeedsLook == true)
    }

    @Test func incidents() {
        let p = panel(.incidents)
        #expect(p.status.mark == .down)
        #expect(p.status.title == "5 incidents")
        #expect(p.status.subtitle == "5 checks down · 63 of 68 passing")
        #expect(p.status.count == 5)
        #expect(p.status.counts == HealthCounts(up: 63, warning: 0, down: 5, unknown: 0))
        #expect(p.status.tuiTitle == "5 INCIDENTS")
        // topo's order: by health, then name. The app doesn't re-sort.
        #expect(p.seen?.problems?.map(\.name) == ["San Jose", "Seattle MacBook", "Seattle Windows"])
        #expect(p.seen?.problems?.map(\.note) == ["1 down", "1 down", "3 down"])
        let a = p.attention!
        #expect(a.items.count == 3)
        #expect(a.total == 17)
        #expect(a.more == 14)
        #expect(a.items[0].route == ["Primary BandwagonHost", "Oracle Exit A"])
        #expect(a.items[0].pill == Pill(text: "OPEN", mark: .down))
        #expect(a.items[0].observerName == "Seattle MacBook")
        #expect(Words.span(since: a.items[0].since!, now: a.now) == "4 min")
        let bwh = p.servers[1]
        #expect(bwh.pill.text == "AFFECTED")
        #expect(bwh.mark == .degraded)
        #expect(bwh.services.first?.note == "affected")
        guard case .server(let mac, _)? = p.mac else { Issue.record("no mac"); return }
        #expect(mac.observes.first?.text == "14 checks · 1 down")
    }

    @Test func attentionLimitFive() {
        let p = panel(.incidents, settings: settings(limit: 5))
        #expect(p.attention?.items.count == 5)
        #expect(p.attention?.more == 12)
    }

    @Test func incomplete() {
        let p = panel(.incomplete)
        #expect(p.status.mark == .unknown)
        #expect(p.status.title == "Evidence incomplete")
        #expect(p.status.shortTitle == "Incomplete")
        #expect(p.status.count == 7)
        #expect(p.status.observersLive == 10)
        #expect(p.seen?.problems?.map(\.note) == ["silent 3m"])
        #expect(p.attention?.items.map(\.pill.text) == ["UNKNOWN", "UNKNOWN"])
        #expect(p.applications?.rows[0].note == "2 unknown")
        #expect(p.applications?.rows[0].mark == .unknown)
    }

    @Test func offline() {
        let p = panel(.offline)
        #expect(p.status.isBlind)
        #expect(p.status.kind == .blind(.collectorUnreachable))
        #expect(p.status.mark == .offline)
        #expect(p.status.title == "Offline")
        #expect(p.status.counts == nil, "unknown, not zero")
        #expect(p.status.count == nil)
        #expect(p.status.history == "Last snapshot 3 min ago said all clear. Nothing current is known.")
        #expect(p.status.big.digits == "--")
        #expect(p.chrome.connection == .unreachable)
        #expect(p.seen?.isKnown == false)
        #expect(p.attention == nil)
        #expect(p.servers.allSatisfy { $0.mark == .offline && $0.cpu.percent == nil })
    }

    @Test func staleLeaseLapses() {
        let live = panel(.stale, after: 10)
        #expect(live.status.mark == .down)
        let p = panel(.stale, after: 30)
        #expect(p.status.kind == .blind(.leaseLapsed))
        #expect(p.status.mark == .offline)
        #expect(p.status.lastKnown?.text == "5 INCIDENTS")
        #expect(p.status.history == "Last snapshot 30 s ago said 5 incidents. Nothing current is known.")
        // Withheld, not gone: names stay, every health is withheld.
        let apps = p.applications!
        #expect(!apps.isCurrent)
        #expect(apps.rows.allSatisfy { $0.mark == .offline && $0.services.allSatisfy { $0 == .offline } })
        #expect(p.servers.allSatisfy { $0.isWithheld && $0.pill.text == "CACHED" && $0.memory.percent == nil })
        #expect(p.servers[0].age == "last reading 34 s ago")
        #expect(p.attention == nil)
    }

    @Test func rowsLapseOnTheirOwnDeadline() {
        // 15 s after the last frame its rows have passed valid_until while
        // the lease (30 s) still holds.
        let p = panel(.stale, after: 15)
        #expect(p.status.kind == .blind(.verdictExpired))
        #expect(p.status.mark == .offline)
    }

    @Test func stoppedAndRestarting() {
        let at = origin.addingTimeInterval(9)
        let p = panel(.stopped, after: 6, engine: .restarting(at: at))
        #expect(p.status.kind == .blind(.engineStopped(restartAt: at)))
        #expect(p.status.subtitle == "topo stopped · restarting in 3 s")
        #expect(p.chrome.connectionText == "Restarting topo in 3 s")
    }

    @Test func errorFramesAreNotContent() {
        let p = panel(.errorFrame, after: 6)
        #expect(p.status.mark == .up)
        #expect(p.status.title == "All clear")
    }

    @Test func unknownNode() {
        var s = settings()
        s.sections.serverNodes = ["oracle-ny", "old-box"]
        let p = panel(.unknownNode, settings: s)
        #expect(p.servers.map(\.id) == ["oracle-ny", "old-box"])
        let missing = p.servers[1]
        #expect(missing.isMissing)
        #expect(missing.mark == .unknown)
        #expect(missing.cpu.percent == nil)
        #expect(missing.place == "Not in the topology")
    }

    @Test func serverCards() {
        let p = panel(.clear)
        let ny = p.servers[0]
        #expect(ny.name == "Oracle New York")
        #expect(ny.subtitle == "host · Oracle · New York")
        #expect(ny.pill.text == "UP")
        #expect(ny.cpu == .init(percent: 26.3, limit: 90, detail: "8 CPUs"))
        #expect(ny.memory.detail == "7.4 / 16 GiB")
        #expect(ny.disk.detail == "150 / 256 GiB")
        #expect(ny.servicesSummary == "4 services · 3 up · 1 not monitored")
        // Trouble first, as the card lists them.
        #expect(ny.services.first?.name == "Nightly Backup")
        #expect(ny.services.first?.note == "not monitored")
        #expect(ny.services.first?.mark == .unknown)
        #expect(ny.age == "8 s ago")
        #expect(p.servers[1].servicesSummary == "6 services · all up")
        #expect(p.servers[1].memory.isOverLimit == false)
    }

    @Test func waitingForTopo() {
        let s = settings()
        let reading = ReaderPolicy().evaluate(at: origin)
        #expect(SectionBuilder.panel(PanelInput(reading: reading, engine: .starting, settings: s)).status.kind == .blind(.starting))
        #expect(SectionBuilder.panel(PanelInput(reading: reading, engine: .notFound, settings: s)).status.kind == .blind(.topoNotFound))
        #expect(SectionBuilder.panel(PanelInput(reading: reading, engine: .tooOld, settings: s)).status.kind == .blind(.topoTooOld))
    }

    @Test func statusItem() {
        let menu = Settings.Appearance.MenuBar()
        var words = menu
        words.show = .words
        var symbol = menu
        symbol.show = .symbol
        let inc = StatusItemModel(status: panel(.incidents).status, appearance: menu)
        #expect(inc.text == "5")
        #expect(inc.accessibilityLabel == "Topophany: 5 incidents, updated 4 seconds ago")
        #expect(StatusItemModel(status: panel(.clear).status, appearance: menu).text == "")
        #expect(StatusItemModel(status: panel(.incomplete).status, appearance: words).text == "Incomplete")
        #expect(StatusItemModel(status: panel(.incomplete).status, appearance: words).tuiText == "INCOMPLETE")
        #expect(StatusItemModel(status: panel(.offline).status, appearance: words).text == "Offline")
        #expect(StatusItemModel(status: panel(.offline).status, appearance: menu).text == "")
        #expect(StatusItemModel(status: panel(.degraded).status, appearance: symbol).text == "")
    }

    @Test func sectionOrderAndChoices() {
        var s = settings(servers: false, mac: .local)
        s.sections.move(.mac, to: 1)
        s.sections.applicationsOnly = ["site", "proxy"]
        s.sections.seen = false
        let p = panel(.clear, settings: s)
        #expect(p.sections.map(\.id) == [.mac, .applications])
        #expect(p.applications?.rows.map(\.name) == ["Proxy chain", "Main site"])
    }

    @Test func observerView() {
        var s = settings()
        s.topo.observer = "seattle-macbook"
        #expect(panel(.clear, settings: s).chrome.view == "Seattle MacBook")
    }
}

@Suite struct WordsTests {
    init() { L10n.force("en") }

    @Test func ages() {
        let t = origin
        #expect(Words.ago(t, now: t.addingTimeInterval(4)) == "4 s ago")
        #expect(Words.ago(t, now: t.addingTimeInterval(180)) == "3 min ago")
        #expect(Words.ago(t, now: t.addingTimeInterval(7200)) == "2 h ago")
        #expect(Words.ago(t, now: t.addingTimeInterval(4), style: .compact) == "4s ago")
        #expect(Words.span(since: t, now: t.addingTimeInterval(240)) == "4 min")
        #expect(Words.ago(t, now: t.addingTimeInterval(-5)) == "0 s ago")
    }

    @Test func sizesAndRates() {
        #expect(Words.gib(Int64(7.4 * Double(1 << 30))) == "7.4")
        #expect(Words.gib(16 << 30) == "16")
        #expect(Words.gib(150 << 30) == "150")
        #expect(Words.gb(107_100_000_000) == "107.1")
        #expect(Words.rate(343_900) == "343.9 kB/s")
        #expect(Words.rate(12) == "12 B/s")
        #expect(Words.rate(2_500_000) == "2.5 MB/s")
        #expect(Words.clock(minutes: 72) == "1:12")
    }

    @Test func pills() {
        #expect(Pill.state("open", health: .down) == Pill(text: "OPEN", mark: .down))
        #expect(Pill.state("glowing", health: .degraded) == Pill(text: "GLOWING", mark: .degraded))
        #expect(Pill.state("", health: .up) == Pill(text: "UP", mark: .up))
    }
}
