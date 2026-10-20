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
    let request = TemplateCompiler().request(for: s, revision: 1, serviceCards: true)
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
        #expect(p.sections.map(\.id) == [.seen, .applications, .fleet, .servers, .zones, .mac])
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
        #expect(p.status.history == "Last snapshot 3 min ago said **all clear**. Nothing current is known.")
        #expect(p.status.big.digits == "--")
        #expect(p.chrome.connection == .unreachable)
        #expect(p.seen?.isKnown == false)
        #expect(p.seen?.total == 11, "from history")
        #expect(p.attention == nil)
        #expect(p.servers.map(\.name) == ["Oracle New York", "BandwagonHost LA"])
        #expect(p.servers.allSatisfy { $0.mark == .offline && $0.cpu.percent == nil && $0.pill.text == "CACHED" })
        // Names from the last snapshot; no health.
        let apps = p.applications!
        #expect(!apps.isCurrent)
        #expect(apps.rows.count == 6)
        #expect(apps.rows.allSatisfy { $0.mark == .offline && $0.note == "cached" })
    }

    @Test func staleLeaseLapses() {
        let live = panel(.stale, after: 10)
        #expect(live.status.mark == .down)
        let p = panel(.stale, after: 30)
        #expect(p.status.kind == .blind(.leaseLapsed))
        #expect(p.status.mark == .offline)
        #expect(p.status.lastKnown?.text == "5 INCIDENTS")
        #expect(p.status.history == "Last snapshot 30 s ago said **5 incidents**. Nothing current is known.")
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
        #expect(p.chrome.connection == .connected, "a verdict deadline does not disconnect the collector")
        #expect(p.status.counts == nil, "connection status must not extend evidence validity")
    }

    @Test func expiredEvidenceDoesNotFlapTheConnection() {
        let s = settings()
        let request = TemplateCompiler().request(for: s, revision: 1)
        let initial = FixtureEngine.reading(.clear, request: request, origin: origin, after: 4).frame!
        var policy = ReaderPolicy()
        var sequence: UInt64 = 0
        func receive(_ frame: Frame, after seconds: TimeInterval) -> PanelModel {
            var next = frame
            sequence += 1
            next.sequence = sequence
            let now = origin.addingTimeInterval(seconds)
            next.generatedAt = now
            next.publisherExpiresAt = now.addingTimeInterval(30)
            policy.receive(next, at: now)
            return SectionBuilder.panel(PanelInput(reading: policy.evaluate(at: now), engine: .running, settings: s))
        }

        #expect(receive(initial, after: 4).chrome.connection == .connected)
        for (offset, reason, blind) in [
            (5.0, "sample_expired", StatusSection.Blind.verdictExpired),
            (6.0, "source_expired", .snapshotExpired),
        ] {
            var expired = initial
            let index = expired.rows.firstIndex { $0.metric == "summary.verdict" }!
            expired.rows[index].value = .none
            expired.rows[index].reason = reason
            expired.rows[index].freshness = "stale"
            let p = receive(expired, after: offset)
            #expect(p.status.kind == .blind(blind))
            #expect(p.status.counts == nil)
            #expect(p.chrome.connection == .connected)
            #expect(receive(initial, after: offset + 0.5).chrome.connection == .connected)
        }

        var unavailable = initial
        let index = unavailable.rows.firstIndex { $0.metric == "summary.verdict" }!
        unavailable.rows[index].value = .none
        unavailable.rows[index].reason = "source_unavailable"
        #expect(receive(unavailable, after: 7).chrome.connection == .unreachable)
        #expect(receive(initial, after: 8).chrome.connection == .connected)
        let lapsed = SectionBuilder.panel(PanelInput(reading: policy.evaluate(at: origin.addingTimeInterval(38)),
                                                   engine: .running, settings: s))
        #expect(lapsed.status.kind == .blind(.leaseLapsed))
        #expect(!lapsed.chrome.isLive, "a dead publisher must still disconnect")
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

    func pinned(_ ids: [String] = ["vless-entry", "main-site", "workers-api", "nightly-backup", "old-service"]) -> Settings {
        var s = settings()
        s.sections.services = true
        s.sections.serviceIDs = ids
        return s
    }

    /// Off until a service is pinned; then after Applications.
    @Test func servicesSection() {
        #expect(panel(.incidents).section(.services) == nil)
        let p = panel(.incidents, settings: pinned())
        #expect(p.sections.map(\.id) == [.seen, .attention, .applications, .services, .fleet, .servers, .zones, .mac])
        #expect(p.services.map(\.id) == ["vless-entry", "main-site", "workers-api", "nightly-backup", "old-service"])
    }

    @Test func serviceCards() {
        let p = panel(.incidents, settings: pinned())
        let entry = p.services[0]
        #expect(entry.name == "VLESS+Reality Entry (Primary)")
        #expect(entry.subtitle == "Proxy chain · on BandwagonHost LA")
        #expect(entry.pill.text == "WARN")
        #expect(entry.mark == .degraded)
        // Seen from: an observer a row, worst first, by its place.
        #expect(entry.observers.map(\.label) == ["Seattle", "San Jose", "New York", "Frankfurt"])
        #expect(entry.observers[0].marks == [.down])
        #expect(entry.observers[0].p50 == 46)
        #expect(entry.observers[0].up24h == 98.3)
        guard case .samples(let samples) = entry.observers[0].history else { Issue.record("no samples"); return }
        #expect(samples.count == 36)
        #expect(samples.last == .fail)
        #expect(entry.checks == [.down, .down, .up, .up])
        #expect(entry.checksText == "4 checks · 2 failing")
        #expect(entry.edge == nil)
        #expect(entry.age == "8 s ago")

        let site = p.services[1]
        #expect(site.pill.text == "UP")
        #expect(site.edge?.name == "Cloudflare")
        #expect(site.colos == ["SJC", "FRA"])
        #expect(site.checksText == "3 checks · all passing")
        #expect(site.dependsOn.map(\.name) == ["PostgreSQL"])
        #expect(site.knownAt?.host == "www.example.invalid")
        #expect(site.endpoints.map(\.mark) == [.up, .up])

        // Run on an edge, the edge is what stands in front.
        #expect(p.services[2].edge?.provider == "Cloudflare")
        #expect(p.services[2].host.kind == "edge")

        let backup = p.services[3]
        #expect(backup.isUnmonitored)
        #expect(backup.observers.isEmpty)
        #expect(backup.checksText == "not monitored")
        #expect(backup.quiet == ("Not monitored", "no check measures it"))
        #expect(backup.pill.text == "UNKNOWN")

        let gone = p.services[4]
        #expect(gone.isMissing)
        #expect(gone.subtitle == "Not in the topology")
        #expect(gone.mark == .unknown)
    }

    /// Scoped to an observer whose checks don't measure it, a service other
    /// observers' checks do is not seen from here, not unmonitored.
    @Test func serviceSeenElsewhere() {
        let here = SectionBuilder.service(ServiceCard(id: "vless", name: "VLESS", health: .unknown, monitored: false, elsewhere: true),
                                          withheld: false, now: origin)
        #expect(here.isUnmonitored && here.isElsewhere)
        #expect(here.quiet == ("Not seen from here", "others check it"))
        #expect(here.checksText == "not seen from here")
        let seen = SectionBuilder.service(ServiceCard(id: "blog", name: "Blog", health: .up, elsewhere: true), withheld: false, now: origin)
        #expect(!seen.isElsewhere)
        let unscoped = SectionBuilder.service(ServiceCard(id: "job", name: "Job", health: .unknown, monitored: false), withheld: false, now: origin)
        #expect(!unscoped.isElsewhere && unscoped.quiet.title == "Not monitored")
    }

    /// Offline, the last card is history: names stay, every reading is
    /// withheld, the samples too.
    @Test func serviceCardsOffline() {
        let p = panel(.offline, settings: pinned(["vless-entry"]))
        let c = p.services[0]
        #expect(c.isWithheld)
        #expect(c.pill == .cached)
        #expect(c.observers.allSatisfy { $0.history == .withheld && $0.p50 == nil && $0.up24h == nil })
        #expect(c.observers.flatMap(\.marks).allSatisfy { $0 == .offline })
        #expect(c.name == "VLESS+Reality Entry (Primary)")
        #expect(c.age.hasPrefix("last reading"))
    }

    /// A check past its own deadline is drawn unknown, its numbers gone,
    /// while the card's other checks stay current.
    @Test func aCheckPastItsDeadline() {
        let g = origin
        let card = ServiceCard(
            id: "blog", name: "Blog", health: .up,
            seenFrom: [.init(observer: .init(id: "sj", name: "San Jose"), label: "San Jose", health: .up,
                             checks: [.init(id: "a", name: "a", health: .up, sampledAt: g, validUntil: g.addingTimeInterval(5),
                                            latency: .init(p50: 40, p95: 50), up24h: 99, colo: "SJC",
                                            samples: .init(interval: 10, slots: [.init(.ok, elapsed: 40)]))]),
                       .init(observer: .init(id: "fra", name: "Frankfurt"), label: "Frankfurt", health: .up,
                             checks: [.init(id: "b", name: "b", health: .up, sampledAt: g, validUntil: g.addingTimeInterval(30),
                                            latency: .init(p50: 300, p95: 350), up24h: 98, colo: "FRA",
                                            samples: .init(interval: 10, slots: [.init(.ok, elapsed: 300)]))])])
        let row = Row(id: "service-1", metric: "service.card", select: .init(service: "blog"), value: .serviceCard(card), health: .up,
                      validUntil: g.addingTimeInterval(15))
        var policy = ReaderPolicy()
        policy.receive(Frame(instance: "i", sequence: 1, generatedAt: g, publisherExpiresAt: g.addingTimeInterval(30), rows: [row]), at: g)
        let c = SectionBuilder.services(policy.evaluate(at: g.addingTimeInterval(8)), ids: ["blog"])[0]
        #expect(!c.isWithheld)
        #expect(c.observers[0].marks == [.unknown])
        #expect(c.observers[0].p50 == nil)
        #expect(c.observers[0].up24h == nil)
        #expect(c.observers[0].history == .withheld)
        #expect(c.observers[1].p50 == 300)
        #expect(c.colos == ["FRA"])
        #expect(c.checksText == "2 checks · 1 unknown")
    }

    /// A check whose history `topo` doesn't hold yet draws no samples;
    /// one past its deadline, or in a view that isn't fresh, is withheld.
    @Test func samplesNotHeldYet() {
        let g = origin
        func check(_ freshness: String) -> ServiceCard.Check {
            .init(id: freshness, name: freshness, health: freshness == "fresh" ? .up : .unknown, freshness: freshness, sampledAt: g,
                  validUntil: g.addingTimeInterval(30), latency: .init(p50: 40, p95: 50), up24h: 99,
                  samples: .init(interval: 10, slots: nil))
        }
        let card = ServiceCard(id: "blog", name: "Blog", health: .up, seenFrom: [
            .init(observer: .init(id: "a", name: "A"), label: "A", health: .up, checks: [check("fresh")]),
            .init(observer: .init(id: "b", name: "B"), label: "B", health: .unknown, checks: [check("stale")]),
        ])
        let row = Row(id: "service-1", metric: "service.card", select: .init(service: "blog"), value: .serviceCard(card), health: .up,
                      validUntil: g.addingTimeInterval(15))
        var policy = ReaderPolicy()
        policy.receive(Frame(instance: "i", sequence: 1, generatedAt: g, publisherExpiresAt: g.addingTimeInterval(30), rows: [row]), at: g)
        let c = SectionBuilder.services(policy.evaluate(at: g.addingTimeInterval(4)), ids: ["blog"])[0]
        #expect(c.observers.map(\.history) == [ServiceCardModel.History.none, .withheld])
        #expect(c.observers[0].p50 == 40)
        #expect(c.observers[1].p50 == nil)
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
        #expect(p.sections.map(\.id) == [.mac, .applications, .zones])
        #expect(p.applications?.rows.map(\.name) == ["Proxy chain", "Main site"])
    }

    @Test func observerView() {
        var s = settings()
        s.topo.observer = "seattle-macbook"
        #expect(panel(.clear, settings: s).chrome.view == "Seattle MacBook")
    }

    /// The panel at its shortest keeps its own header, Status and footer,
    /// with This Mac's four readings and two time zones between, whatever
    /// the panel shows.
    @Test func shortestPanel() throws {
        var s = settings(mac: .off)
        s.sections.zones = false
        let p = panel(.incidents, settings: s)
        let shortest = p.shortest
        #expect(shortest.chrome == p.chrome)
        #expect(shortest.status == p.status)
        #expect(shortest.alert == p.alert)
        #expect(shortest.pinStatus == p.pinStatus)
        #expect(shortest.sections.map(\.id) == [.mac, .zones])
        guard case .local(let l)? = shortest.mac else { Issue.record("no local readings"); return }
        #expect(l.readings == [.cpu, .memory, .storage, .network])
        #expect(l.cpu != nil && l.memory != nil && l.storage != nil && l.network != nil && l.battery == nil)
        let zones = try #require(shortest.zones?.zones)
        #expect(zones.count == 2)
        #expect(zones.filter(\.isHere).count == 1)
        #expect(Set(zones.map(\.id)).count == 2)
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
