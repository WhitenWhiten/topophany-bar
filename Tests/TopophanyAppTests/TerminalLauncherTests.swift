import Foundation
import Testing
import TopophanyKit

struct TerminalLauncherTests {
    @MainActor @Test func modesAndQuoting() {
        var s = Settings(); s.topo.profile = "desktop"; s.topo.observer = "obs"
        #expect(TerminalLauncher.arguments(s, focus: nil) == ["--profile", "desktop", "--observer", "obs"])
        s.topo.source = "direct"
        #expect(TerminalLauncher.arguments(s, focus: nil) == ["--source", "direct", "--profile", "desktop"])
        s.topo.source = "preview"; s.topo.scenario = 2
        #expect(TerminalLauncher.arguments(s, focus: nil) == ["preview", "--scenario", "2", "--observer", "obs"])
        #expect(TerminalLauncher.quote("a'b") == "'a'\\''b'")
    }
}
