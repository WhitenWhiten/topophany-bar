import Foundation
import Testing
@testable import TopophanyKit

struct CoverageTests {
    @Test func invalidCoverageIsWithheldWithoutLosingVerdict() throws {
        for counts in [#""services":2,"known":3"#, #""services":-1,"known":0"#] {
            let data = Data((#"{"state":"clear","coverage":{"observer":"home","# + counts + "}}").utf8)
            let verdict = try JSONDecoder().decode(Verdict.self, from: data)
            #expect(verdict.state == .clear)
            #expect(verdict.coverage == nil)
        }
        let data = Data(#"{"state":"clear","coverage":{"observer":"home","services":23,"known":3}}"#.utf8)
        let verdict = try JSONDecoder().decode(Verdict.self, from: data)
        #expect(verdict.coverage?.known == 3)
        #expect(verdict.coverage?.services == 23)
    }
}
