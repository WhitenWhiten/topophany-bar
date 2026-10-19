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
