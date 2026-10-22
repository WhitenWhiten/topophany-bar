import Foundation
import Testing
@testable import TopophanyKit

struct DirectTests {
    @Test func settingsAndTemplates() throws {
        for source in ["client", "preview", "direct", "future"] {
            let data = Data("{\"topo\":{\"source\":\"\(source)\",\"path\":\"/synthetic/topo\",\"profileRevision\":23}}".utf8)
            var s = try JSONDecoder().decode(Settings.self, from: data)
            #expect(s.topo.source == source)
            #expect(s.topo.path == "/synthetic/topo")
            s.topo.profile = "desktop"
            s.topo.profileRevision = "rev-a"
            s.sections.servers = true
            s.sections.serverNodes = ["bs-a.system1", "bs-a.system1"]
            let r = TemplateCompiler().request(for: s, revision: 1, widgets: .init(nodes: ["bs-a.system1", "bs-b.system1"]), listServers: true, serviceCards: true)
            #expect(r.source == source)
            if source == "direct" {
                #expect(r.template.rows.map(\.metric) == ["sources.status", "servers.list", "server.card", "server.card"])
                #expect(r.profileRevision == "rev-a")
                #expect(r.lang == nil && r.scenario == nil && r.credentials.isEmpty)
            } else { #expect(r.template.rows.first?.metric == "summary.verdict") }
        }
        let old = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(old.topo.source == "client")
    }
    /// Direct reads every selected system; a view saved for another mode never
    /// reaches the request `topo` validates.
    @Test func directRequestsCarryNoCollectorView() {
        var s = Settings(); s.topo.source = "direct"; s.topo.profile = "desktop"; s.topo.observer = "home"
        let needs = TemplateCompiler.WidgetNeeds(nodes: ["bs-a.system1"])
        let r = TemplateCompiler().request(for: s, revision: 1, widgets: needs)
        #expect(r.observer.isEmpty)
        #expect(r.source == "direct" && r.profile == "desktop")
        s.topo.observer = ""
        #expect(r == TemplateCompiler().request(for: s, revision: 1, widgets: needs))
    }
    @Test func capabilitiesAreScoped() throws {
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"sources":["client","preview","direct"],"metrics":[{"name":"summary.verdict","sources":["client"]}],"direct":{"schema":1,"config_api":1,"adapters":["beszel"],"retry":true,"limits":{"sources_per_profile":64,"objects_per_source":20,"objects_per_profile":256,"template_rows":128}}}"#.utf8))
        #expect(caps.isUsable && caps.supports(source: "direct"))
        #expect(!caps.supports(metric: "summary.verdict", source: "direct"))
        #expect(caps.supports(metric: "summary.verdict", source: "preview"))
        var s = Settings(); s.topo.source = "direct"; s.topo.profile = "desktop"
        let r = TemplateCompiler().request(for: s, revision: 1).supported(by: caps)
        #expect(throws: SourceProblem.self) { try r.validate(using: caps) }
        let old = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"sources":["client","preview"]}"#.utf8))
        #expect(!old.supports(source: "direct"))
    }
    @Test func optionalOriginAndIntegers() throws {
        let data = Data(#"{"id":"bs-a.object","name":"合成","origin":{"adapter":42},"resources":[{"cpu":{"percent":12.5},"memory":{"used_bytes":9007199254740993},"origin":false}],"extra":true}"#.utf8)
        let card = try JSONDecoder().decode(ServerCard.self, from: data)
        #expect(card.origin == nil)
        #expect(card.resources.first?.origin == nil)
        #expect(card.resources.first?.cpu?.percent == 12.5)
        #expect(card.resources.first?.memory?.usedBytes == 9007199254740993)
        let number = try JSONDecoder().decode(JSONValue.self, from: Data("9007199254740993".utf8))
        #expect(number == .integer(9007199254740993))
    }
    @Test func datasetIsolationAndRejectedReplacement() {
        let now = Date()
        var first = Frame(instance: "one", sequence: 1, source: "direct", generatedAt: now,
                          publisherExpiresAt: now.addingTimeInterval(30), rows: [
                            Row(id: "server", metric: "server.card", value: .other(.string("identity A")), health: .unknown, validUntil: now.addingTimeInterval(20))])
        first.profile = "desktop"; first.datasetID = "A"
        var reader = ReaderPolicy(); reader.receive(first, at: now)
        #expect(!reader.lastValues.isEmpty)
        var rejected = first; rejected.lifecycle = .error; rejected.datasetID = "B"
        reader.receive(rejected, at: now)
        #expect(reader.frame?.datasetID == "A")
        var second = first; second.sequence = 2; second.datasetID = "B"; second.rows = []
        reader.receive(second, at: now)
        #expect(reader.lastValues.isEmpty && reader.lastKnown == nil)
        reader.receive(first, at: now)
        #expect(reader.frame?.datasetID == "B")
    }

    @Test func rowBudgetIsExplicit() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(contentsOf: root.appending(path: "docs/contracts/direct-v1/fixtures/capabilities.json")))
        var s = Settings(); s.topo.source = "direct"; s.topo.profile = "desktop"; s.sections.servers = true
        s.sections.serverNodes = (0..<127).map { "bs-source.node-\($0)" }
        let r = TemplateCompiler().request(for: s, revision: 1)
        #expect(r.template.rows.count == 129)
        do { try r.validate(using: caps); Issue.record("expected row limit") }
        catch { #expect((error as? SourceProblem)?.code == "template_limit") }
    }

}
