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
    @MainActor @Test func investigationsFollowSourceBoundaries() {
        var s = Settings(); s.topo.profile = "production"; s.topo.observer = "home"
        #expect(TerminalLauncher.relatedArguments(s)?.suffix(3) == ["--page", "incidents", "--related-incidents"])
        #expect(TerminalLauncher.comparisonArguments(s, service: "web") == ["compare", "--service", "web", "--step", "5m", "--span", "1h", "--profile", "production"])
        s.topo.source = "direct"
        #expect(TerminalLauncher.relatedArguments(s) == nil)
        #expect(TerminalLauncher.comparisonArguments(s, service: "web") == nil)
        #expect(TerminalLauncher.diagnosticArguments(s) == ["doctor", "--source", "direct", "--profile", "production"])
        s.topo.source = "preview"
        #expect(TerminalLauncher.diagnosticArguments(s) == nil)
    }
}
