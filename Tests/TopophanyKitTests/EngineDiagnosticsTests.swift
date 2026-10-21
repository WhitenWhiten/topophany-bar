import Testing
import TopophanyKit

@Suite struct EngineDiagnosticsTests {
    @Test func boundsBacklogWithoutLosingTheLatestLines() {
        let buffer = EngineDiagnostics()
        var notifications = 0
        for i in 0..<20_000 {
            if buffer.append("line \(i)") { notifications += 1 }
        }
        #expect(notifications == 1)
        #expect(buffer.drain() == (19_950..<20_000).map { "line \($0)" })
        #expect(buffer.drain().isEmpty)
        #expect(buffer.append("after draining"))
        #expect(buffer.drain() == ["after draining"])
    }

    @Test func boundsEachLine() {
        let buffer = EngineDiagnostics()
        #expect(buffer.append(String(repeating: "x", count: 20_000)))
        #expect(buffer.drain().first?.count == 500)
    }
}
