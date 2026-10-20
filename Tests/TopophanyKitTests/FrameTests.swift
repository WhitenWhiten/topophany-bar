import Foundation
import Testing
@testable import TopophanyKit

@Suite struct TimestampTests {
    @Test func parsesGoTimes() throws {
        let base = try #require(Timestamp.parse("2026-10-18T13:30:37Z"))
        #expect(Timestamp.format(base) == "2026-10-18T13:30:37Z")
        let nano = try #require(Timestamp.parse("2026-10-18T13:30:37.123456789Z"))
        #expect(abs(nano.timeIntervalSince(base) - 0.123456789) < 1e-6)
        let offset = try #require(Timestamp.parse("2026-10-18T06:30:37-07:00"))
        #expect(offset == base)
        #expect(Timestamp.parse("2026-10-18 13:30:37Z") == nil)
        #expect(Timestamp.parse("2026-13-18T13:30:37Z") == nil)
        #expect(Timestamp.parse("2026-10-18T13:30:37") == nil)
        #expect(Timestamp.parse("0001-01-01T00:00:00Z") == nil)
        #expect(Timestamp.parse("") == nil)
    }

    @Test func formatsEpoch() {
        #expect(Timestamp.format(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00Z")
        #expect(Timestamp.format(Date(timeIntervalSince1970: 951_782_400)) == "2000-02-29T00:00:00Z")
    }
}

@Suite struct FrameTests {
    static let running = #"""
    {"schema":1,"name":"stream","request_id":"settings-42","config_revision":"r1","instance":"i1","sequence":1842,
     "source":"client","project":"homelab","observer":"","lifecycle":"running","future_field":{"x":1},
     "generated_at":"2026-10-18T13:30:37Z","publisher_expires_at":"2026-10-18T13:31:07Z",
     "title":"Topophany","icon":"","bar_row":"status",
     "rows":[
      {"id":"status","label":"","metric":"summary.verdict","visual":"status","select":{},
       "value":{"state":"incidents","glyph":"✖","text":"5 INCIDENTS","extra":true,
        "counts":{"up":63,"warning":0,"down":5,"unknown":0,"paused":0,"maintenance":0},
        "configured":68,"incidents":5,"observers":{"live":11,"all":11}},
       "text":"5 INCIDENTS","health":"down","freshness":"fresh",
       "sampled_at":"2026-10-18T13:30:33Z","valid_until":"2026-10-18T13:30:48Z"},
      {"id":"attention","metric":"attention.list","visual":"list","limit":3,
       "value":{"total":17,"items":[
        {"kind":"incident","id":"inc-7f3a","title":"Seattle MacBook → Primary BandwagonHost → Oracle Exit A",
         "route":["Primary BandwagonHost","Oracle Exit A"],"observer":"seattle-macbook","observer_name":"Seattle MacBook",
         "since":"2026-10-18T13:26:02Z","health":"down","state":"OPEN"},
        {"kind":"service","id":"svc","title":"VLESS","route":["VLESS"],"observer":"","observer_name":"",
         "since":null,"health":"sideways","state":"glowing"}]},
       "text":"17","health":"down","freshness":"fresh","valid_until":"2026-10-18T13:30:48Z"},
      {"id":"nyc","metric":"server.card","visual":"card","select":{"node":"oracle-ny"},
       "value":null,"text":"unknown","health":"unknown","freshness":"unavailable","reason":"entity_missing"},
      {"id":"cpu","metric":"host.cpu.used_percent","visual":"bar","value":26.3,"unit":"percent","text":"26.3%",
       "health":"up","freshness":"fresh","valid_until":"2026-10-18T13:30:48Z"},
      {"id":"seen","metric":"observers.verdicts","visual":"list","value":{"not":"a list"},
       "text":"","health":"up","freshness":"fresh","valid_until":"2026-10-18T13:30:48Z"}
     ]}
    """#

    @Test func decodesRunningFrame() throws {
        let f = try JSONDecoder().decode(Frame.self, from: Data(Self.running.utf8))
        #expect(f.lifecycle == .running)
        #expect(f.requestID == "settings-42")
        #expect(f.sequence == 1842)
        #expect(f.project == "homelab")
        #expect(f.barRow == "status")
        #expect(f.rows.count == 5)

        guard case .verdict(let v) = f.row("status")?.value else { Issue.record("no verdict"); return }
        #expect(v.state == .incidents)
        #expect(v.text == "5 INCIDENTS")
        #expect(v.counts?.health.complete?.down == 5)
        #expect(v.counts?.paused == 0)
        #expect(v.configured == 68)
        #expect(v.observers == ObserversLive(live: 11, all: 11))
        #expect(f.row("status")?.health == .down)

        guard case .attention(let a) = f.row("attention")?.value else { Issue.record("no attention"); return }
        #expect(a.total == 17)
        #expect(a.items.count == 2)
        #expect(a.items[0].state == "open")
        #expect(a.items[0].route == ["Primary BandwagonHost", "Oracle Exit A"])
        #expect(a.items[0].since != nil)
        // Unknown words are kept; unknown healths are unknown.
        #expect(a.items[1].state == "glowing")
        #expect(a.items[1].health == .unknown)
        #expect(a.items[1].since == nil)
        #expect(f.row("attention")?.limit == 3)

        #expect(f.row("nyc")?.value == RowValue.none)
        #expect(f.row("nyc")?.reason == "entity_missing")
        #expect(f.row("nyc")?.select?.node == "oracle-ny")
        #expect(f.row("cpu")?.value == .other(.number(26.3)))
        #expect(f.row("seen")?.value == .malformed)
    }

    @Test func decodesErrorFrame() throws {
        let line = #"{"schema":1,"name":"stream","request_id":"settings-43","lifecycle":"error","error":{"code":"invalid_request","message":"row attention: limit must be 1..20"},"generated_at":"2026-10-18T13:30:37Z","publisher_expires_at":"2026-10-18T13:31:07Z","rows":[]}"#
        let f = try JSONDecoder().decode(Frame.self, from: Data(line.utf8))
        #expect(f.lifecycle == .error)
        #expect(f.error?.code == "invalid_request")
        #expect(f.rows.isEmpty)
    }

    @Test func decodesServerCard() throws {
        let line = #"""
        {"id":"oracle-ny","name":"Oracle New York","kind":"host","provider":"Oracle","group":"","where":"New York",
         "health":"up","note":"",
         "resources":[{"check":"oracle-ny-host","observer":"ny-oracle","health":"up","freshness":"fresh",
           "sampled_at":"2026-10-18T13:30:33Z","valid_until":"2026-10-18T13:31:03Z",
           "cpu":{"percent":26.3,"limit":90,"logical":8},
           "memory":{"percent":46.2,"limit":null,"used_bytes":7944011776,"total_bytes":17179869184,"basis":"x"},
           "disk":{"percent":null,"limit":90,"path":"/","used_bytes":null,"total_bytes":274877906944},
           "process":null}],
         "services":[{"id":"main-site","name":"Main Site (Caddy + Blog)","health":"up","monitored":true,"affected":false}],
         "observes":[{"id":"ny-oracle","name":"New York Oracle Cloud","health":"up","state":"clear","live":true,
           "last_seen":"2026-10-18T13:30:33Z","counts":{"up":9,"warning":0,"down":0,"unknown":0}}]}
        """#
        let c = try JSONDecoder().decode(ServerCard.self, from: Data(line.utf8))
        #expect(c.place == "New York")
        let r = try #require(c.resources.first)
        #expect(r.cpu?.percent == 26.3)
        #expect(r.cpu?.logical == 8)
        #expect(r.memory?.limit == nil)
        #expect(r.disk?.percent == nil)
        #expect(r.disk?.totalBytes == 274_877_906_944)
        #expect(r.process == nil)
        #expect(c.services.first?.monitored == true)
        #expect(c.observes.first?.state == .clear)
        #expect(c.observes.first?.counts?.up == 9)
    }
}

@Suite struct ServerListTests {
    @Test func decodesTheList() throws {
        let line = #"""
        {"schema":1,"name":"stream","request_id":"r","config_revision":"c","instance":"i","sequence":1,"source":"client",
         "lifecycle":"running","generated_at":"2026-10-18T13:30:00Z","publisher_expires_at":"2026-10-18T13:30:30Z","rows":[
         {"id":"servers","metric":"servers.list","visual":"list","value":[
           {"id":"oracle-ny","name":"Oracle New York","kind":"host","provider":"Oracle","group":"","where":"New York","health":"up","note":""},
           {"id":"bwh-la","name":"BandwagonHost LA","health":"degraded","note":"affected"}],
          "text":"2 servers","health":"degraded","freshness":"fresh","valid_until":"2026-10-18T13:30:20Z"}]}
        """#
        let f = try JSONDecoder().decode(Frame.self, from: Data(line.utf8))
        guard case .servers(let list) = f.rows.first?.value else {
            Issue.record("not a server list: \(String(describing: f.rows.first?.value))")
            return
        }
        #expect(list.map(\.id) == ["oracle-ny", "bwh-la"])
        #expect(list[0].place == "New York")
        #expect(list[1].health == .degraded)
        #expect(list[1].kind == "")
    }

    @Test func matchesThisMacsName() {
        let list = [ServerListEntry(id: "oracle-ny", name: "Oracle New York"), ServerListEntry(id: "macbook", name: "MacBook Pro"),
                    ServerListEntry(id: "studio", name: "Whiten’s Mac Studio")]
        #expect(ServerListEntry.matching(localHostName: "MacBook", in: list)?.id == "macbook")
        #expect(ServerListEntry.matching(localHostName: "MacBook-Pro", in: list)?.id == "macbook")
        #expect(ServerListEntry.matching(localHostName: "Whitens-Mac-Studio", in: list) == nil)
        #expect(ServerListEntry.matching(localHostName: "Whiten-s-Mac-Studio", in: list)?.id == "studio")
        #expect(ServerListEntry.matching(localHostName: "", in: list) == nil)
        #expect(ServerListEntry.matching(localHostName: "Mac", in: list) == nil)
    }
}

@Suite struct FrameDecoderTests {
    static let a = #"{"schema":1,"name":"stream","lifecycle":"running","sequence":1,"rows":[]}"#
    static let b = #"{"schema":1,"name":"stream","lifecycle":"running","sequence":2,"rows":[]}"#

    func sequences(_ outs: [FrameDecoder.Output]) -> [UInt64?] {
        outs.compactMap { if case .frame(let f, _) = $0 { f.sequence } else { nil } }
    }

    @Test func splitsLinesAcrossChunks() {
        var d = FrameDecoder()
        let all = Data((Self.a + "\n" + Self.b + "\n").utf8)
        var outs: [FrameDecoder.Output] = []
        for i in stride(from: 0, to: all.count, by: 7) {
            outs += d.feed(all.subdata(in: i..<min(all.count, i + 7)))
        }
        #expect(sequences(outs) == [1, 2])
    }

    @Test func toleratesBlankLinesAndCRLF() {
        var d = FrameDecoder()
        let outs = d.feed(Data(("\n\r\n" + Self.a + "\r\n").utf8))
        #expect(sequences(outs) == [1])
    }

    @Test func keepsTheLine() {
        var d = FrameDecoder()
        let outs = d.feed(Data((Self.a + "\n").utf8))
        guard case .frame(_, let line) = outs.first else { Issue.record("no frame"); return }
        #expect(String(decoding: line, as: UTF8.self) == Self.a)
        #expect(FrameDecoder.frame(from: line)?.sequence == 1)
    }

    @Test func dropsOversizedLinesAndGoesOn() {
        var d = FrameDecoder()
        let big = Data(repeating: 0x61, count: FrameDecoder.maxLineBytes + 1)
        var outs = d.feed(big.prefix(600_000))
        outs += d.feed(big.dropFirst(600_000))
        outs += d.feed(Data(("tail\n" + Self.b + "\n").utf8))
        let problems = outs.compactMap { if case .problem(let p) = $0 { p } else { nil } }
        #expect(problems == [.oversized(bytes: FrameDecoder.maxLineBytes + 1 + 4)])
        #expect(sequences(outs) == [2])
    }

    @Test func acceptsALineOfExactlyTheCap() {
        var d = FrameDecoder()
        let pad = String(repeating: " ", count: FrameDecoder.maxLineBytes - Self.a.utf8.count)
        let outs = d.feed(Data((Self.a + pad + "\n").utf8))
        #expect(sequences(outs) == [1])
    }

    @Test func reportsMalformedLines() {
        var d = FrameDecoder()
        let outs = d.feed(Data("{not json}\n{\"schema\":\"x\"}\n".utf8))
        #expect(outs.count == 2)
        for o in outs {
            guard case .problem(.malformed) = o else { Issue.record("expected malformed"); return }
        }
    }

    @Test func finishDecodesTheLastLine() {
        var d = FrameDecoder()
        #expect(d.feed(Data(Self.a.utf8)).isEmpty)
        #expect(sequences(d.finish()) == [1])
    }
}

@Suite struct ServiceCardTests {
    /// PROTOCOL.md §3.3's example, with a few of the shapes a card may take.
    static let card = #"""
    {"id":"blog","name":"Main Site (Caddy + Blog)","application":{"id":"main-site","name":"Main site"},"environment":"","runtime":"",
     "health":"up","note":"","evidence":"inferred","reason":"all checks in this view pass","monitored":true,
     "host":{"id":"app","name":"Oracle New York","kind":"host","provider":"Oracle","where":"New York","health":"up"},
     "seen_from":[{"observer":{"id":"obs-relay","name":"San Jose DigitalOcean"},"label":"San Jose","health":"up",
       "checks":[{"id":"r-app-web","name":"Relay to app web","kind":"http","endpoint":"app-web","health":"up","freshness":"fresh",
         "sampled_at":"2026-10-18T13:30:33Z","valid_until":"2026-10-18T13:31:03Z",
         "latency":{"p50_ms":231,"p95_ms":272},"up_24h":97.6,"first_byte":"origin 98 ms","colo":"SJC",
         "samples":{"interval_seconds":15,"slots":[{"outcome":"ok","elapsed_ms":220},{"outcome":"fail","elapsed_ms":4000},
           {"outcome":"none"},{"outcome":"policy"},{"outcome":"error"},{"outcome":"later"}]}},
         {"id":"r-app-api","name":"Relay to app API","health":"warn","freshness":"never","latency":null,"up_24h":null,
          "first_byte":"","colo":"","samples":{"interval_seconds":15,"slots":null}}]}],
     "endpoints":[{"id":"app-web","network":"public","address":"https://www.example.invalid/","health":"up",
       "via":[{"id":"cf","name":"Cloudflare","kind":"edge","provider":"Cloudflare"}]},
       {"id":"app-web-local","network":"loopback","address":"http://127.0.0.1:8080/","health":"","via":[]}],
     "answered_from":{"pops":["SJC 50%","FRA 50%"],"cache":["DYNAMIC 100%"]},
     "depends_on":[{"id":"postgres","name":"PostgreSQL","health":"up","affected":false,"monitored":true,"host":"PostgreSQL Container"}],
     "used_by":[],"runbook":"https://wiki.example.invalid/runbooks/blog","memo":"The public blog."}
    """#

    @Test func decodesTheExample() throws {
        let c = try JSONDecoder().decode(ServiceCard.self, from: Data(Self.card.utf8))
        #expect(c.application == .init(id: "main-site", name: "Main site"))
        #expect(c.host?.place == "New York")
        #expect(c.monitored == true)
        let o = try #require(c.seenFrom.first)
        #expect(o.observer.id == "obs-relay")
        #expect(o.label == "San Jose")
        let k = o.checks[0]
        #expect(k.latency == .init(p50: 231, p95: 272))
        #expect(k.up24h == 97.6)
        #expect(k.colo == "SJC")
        #expect(k.validUntil == Timestamp.parse("2026-10-18T13:31:03Z"))
        #expect(k.samples?.interval == 15)
        // Elapsed only for a pass; an outcome the app doesn't know is unknown.
        #expect(k.samples?.slots == [.init(.ok, elapsed: 220), .init(.fail), .init(.none), .init(.policy), .init(.error), .init(.unknown)])
        // Unknown is never zero: nothing said is nil, a health it doesn't
        // know is unknown.
        let quiet = o.checks[1]
        #expect(quiet.health == .unknown)
        #expect(quiet.latency == nil)
        #expect(quiet.up24h == nil)
        #expect(quiet.colo == nil)
        #expect(quiet.samples?.slots == nil)
        #expect(c.endpoints.map(\.health) == [.up, nil])
        #expect(c.endpoints[0].via.first?.provider == "Cloudflare")
        #expect(c.answeredFrom?.pops == ["SJC 50%", "FRA 50%"])
        #expect(c.dependsOn.first?.host == "PostgreSQL Container")
    }

    @Test func decodesInARowAndTheList() throws {
        let line = #"""
        {"schema":1,"name":"stream","lifecycle":"running","generated_at":"2026-10-18T13:30:00Z","publisher_expires_at":"2026-10-18T13:30:30Z","rows":[
         {"id":"service-1","metric":"service.card","visual":"card","select":{"service":"blog"},"value":\#(Self.card),
          "health":"up","valid_until":"2026-10-18T13:30:20Z"},
         {"id":"service-2","metric":"service.card","visual":"card","select":{"service":"gone"},"value":null,"health":"unknown",
          "reason":"entity_missing"},
         {"id":"services","metric":"services.list","visual":"list","value":[
           {"id":"blog","name":"Main Site (Caddy + Blog)","application":"Main site","health":"up","note":"","monitored":true,
            "host":{"id":"app","name":"Oracle New York","kind":"host","provider":"Oracle"}},
           {"id":"backup-job","name":"Nightly Backup","application":"","health":"unknown","monitored":false}],
          "text":"2 services","health":"unknown","valid_until":"2026-10-18T13:30:20Z"}]}
        """#
        let f = try JSONDecoder().decode(Frame.self, from: Data(line.utf8))
        #expect(f.rows[0].select?.service == "blog")
        guard case .serviceCard(let c) = f.rows[0].value else { Issue.record("not a card"); return }
        #expect(c.id == "blog")
        #expect(f.rows[1].value == .none)
        #expect(f.rows[1].reason == "entity_missing")
        guard case .services(let list) = f.rows[2].value else { Issue.record("not a list"); return }
        #expect(list.map(\.id) == ["blog", "backup-job"])
        #expect(list[0].application == "Main site")
        #expect(list[0].host?.name == "Oracle New York")
        #expect(list[1].monitored == false)
        #expect(list[1].host == nil)
    }

    /// A request names the service it wants a card of.
    @Test func selectsAService() throws {
        let row = TemplateRow(id: "service-1", metric: "service.card", visual: "card", select: .init(service: "blog"))
        let json = String(decoding: try JSONEncoder().encode(row), as: UTF8.self)
        #expect(json.contains(#""select":{"service":"blog"}"#))
    }
}
