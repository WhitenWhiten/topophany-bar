import Foundation
import Testing
@testable import TopophanyKit

/// This Mac's own checks: the contract with `topo local` and the local stream.
struct LocalTests {
    @Test func capabilitiesSayWhetherTopoReadsThisMac() throws {
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(#"""
            {"protocol":1,"sources":["client","preview","direct","local"],"card_history":true,
             "metrics":[{"name":"check.card","type":"object","sources":["client","collector","local"]}],
             "local":{"schema":1,"config_api":1,"adapters":["mihomo"],"limits":{"checks":4}}}
            """#.utf8))
        #expect(caps.local?.readsMihomo == true && caps.local?.checks == 4)
        #expect(caps.supports(source: "local") && caps.supports(metric: "check.card", source: "local"))
        let r = try #require(TemplateCompiler().localRequest([LocalCheck(id: "lc-a", name: "Proxy engine")], revision: 3, profileRevision: "rev"))
        #expect(throws: Never.self) { try r.supported(by: caps).validate(using: caps) }
        #expect(r.source == "local" && r.requestID == "local-3" && r.profileRevision == "rev")

        // An older topo: no local object, or one without mihomo.
        let old = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"sources":["client","preview","direct"]}"#.utf8))
        #expect(old.local == nil && !old.supports(source: "local"))
        let other = try JSONDecoder().decode(Capabilities.self, from: Data(#"{"protocol":1,"sources":["local"],"local":{"schema":1,"config_api":1,"adapters":["tailscale"]}}"#.utf8))
        #expect(other.local?.readsMihomo == false && !other.supports(source: "local"))
        #expect(TemplateCompiler().localRequest([], revision: 1, profileRevision: "") == nil)
    }

    @Test func aCheckSaysNoExpectationExplicitly() throws {
        var c = LocalCheck(id: "lc-a", name: "Proxy engine")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
        #expect(json["expected_tun"] is NSNull && json["expected_mode"] as? String == "" && json["url"] as? String == "http://127.0.0.1:9090")
        c.expectedTUN = false; c.rootProxy = "Proxy"
        #expect(try JSONDecoder().decode(LocalCheck.self, from: JSONEncoder().encode(c)) == c)
        #expect(LocalCheck().id.hasPrefix("lc-") && LocalCheck().id != LocalCheck().id)
    }

    @Test func onlyThisMacsAddressesAreLocal() {
        for url in ["http://127.0.0.1:9090", "http://127.0.0.1:9097/", "https://localhost:9090", "http://[::1]:9090", "http://127.8.9.10"] {
            #expect(LocalCheck.isLocal(url), "\(url)")
        }
        for url in ["http://192.0.2.1:9090", "http://example.com:9090", "ftp://127.0.0.1", "http://127.0.0.1:9090/configs",
                    "http://user:pw@127.0.0.1:9090", "http://127.0.0.1:9090?secret=x", "127.0.0.1:9090", "http://127.0.0.256", ""] {
            #expect(!LocalCheck.isLocal(url), "\(url)")
        }
    }
}
