import Foundation
import SwiftUI
import Testing
@testable import TopophanyThemes

@Suite struct ThemeTests {
    @Test func builtInsPassValidation() {
        #expect(ThemeStore.builtIn.map(\.id) == ["native", "aurora", "linen", "terminal", "paper", "dusk"])
        for t in ThemeStore.builtIn { #expect(ThemeValidator.refusals(t).isEmpty, "\(t.id): \(ThemeValidator.refusals(t))") }
        // Red-green margins under simulated color-blindness are advisories:
        // the TUI's own palette is under 8 for up/warning.
        #expect(ThemeValidator.validate(ThemeStore.terminal).contains { $0.isAdvisory && $0.description.contains("protanopia") })
        #expect(ThemeStore.builtIn.map(\.renderer) == [.cards, .cards, .cards, .cells, .cells, .cells])
        #expect(ThemeStore.builtIn.map(\.appearance) == [.system, .system, .system, .dark, .light, .dark])
        for t in ThemeStore.builtIn { #expect(ThemeStore().theme(t.id) == t) }
    }

    /// A cards theme that follows the system has its own slots in each
    /// appearance, over the shared ones; the rest stay the system's.
    @Test func tokensPerAppearance() throws {
        let aurora = ThemeStore.aurora
        #expect(aurora.color("accent", dark: true) == RGBA(css: "#2DD4BF"))
        #expect(aurora.color("accent", dark: false) == RGBA(css: "#0D9488"))
        #expect(aurora.color("accent") == nil)
        #expect(aurora.color("up", dark: true) == nil)
        var shared = aurora
        shared.tokens["accent2"] = "#123456"
        shared.dark["accent2"] = nil
        #expect(shared.color("accent2", dark: true) == RGBA(css: "#123456"))
        #expect(shared.color("accent2", dark: false) == RGBA(css: "#7C3AED"))
        // The sets survive the hand-off to widgets; a theme without them
        // writes none.
        let back = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(aurora))
        #expect(back == aurora)
        let native = String(decoding: try JSONEncoder().encode(ThemeStore.native), as: UTF8.self)
        #expect(!native.contains("\"dark\"") && !native.contains("\"light\""))
    }

    /// Only cards draws a theme in both appearances, so only a cards theme
    /// that follows the system may give slots per appearance.
    @Test func tokensPerAppearanceAreForCardsThatFollowTheSystem() {
        let message = "dark and light tokens are for cards themes that follow the system"
        func refusals(_ json: String) -> [String] {
            guard case .failure(.refused(let p)) = ThemeStore.load(Data(json.utf8)) else { return [] }
            return p.map(\.description)
        }
        let cells = ThemeStore.terminalJSON.replacingOccurrences(of: "\"tokens\"", with: ##""dark": {"accent": "#FFFFFF"}, "tokens""##)
        #expect(refusals(cells) == [message])
        #expect(refusals(##"{"schema":1,"id":"x","renderer":"cards","appearance":"dark","light":{"accent":"#000000"}}"##) == [message])
        #expect(refusals(#"{"schema":1,"id":"x","renderer":"cards","dark":{"accent":"teal"}}"#) == ["dark token accent isn't a color: teal"])
        // Status colors are checked in each appearance, with its own.
        let close = ##"{"schema":1,"id":"x","renderer":"cards","light":{"warning":"#FF3B30"}}"##
        #expect(refusals(close) == ["warning and down differ by ΔE 0.0 in light, under 15"])
    }

    /// Cards sets a theme in its family; cells keeps the monospace its grid
    /// is measured in.
    @Test func typeFamilies() {
        #expect(CardsType(scale: 1, theme: ThemeStore.native).design == .default)
        #expect(CardsType(scale: 1, theme: ThemeStore.aurora).design == .default)
        #expect(CardsType(scale: 1, theme: ThemeStore.linen).design == .serif)
        var rounded = ThemeStore.native
        rounded.font = Theme.Font(family: "SF Pro Rounded", size: 13)
        #expect(CardsType(scale: 1, theme: rounded).design == .rounded)
        rounded.font = Theme.Font(family: "Comic Sans", size: 13)
        #expect(CardsType(scale: 1, theme: rounded).design == .default)
    }

    /// Paper's first draft, once DESIGN.md §8's example. Its warning is too
    /// close to down and to unknown for normal vision, so the validator
    /// refuses it, with reasons; the built-in Paper moves both.
    @Test func paperDraftIsRefusedForItsWarningAndDown() {
        let paper = ##"{"schema":1,"id":"paper","name":"Paper","renderer":"cells","appearance":"light","tokens":{"ink":"#F5F0E6","inkHigh":"#ECE5D7","selection":"#E4DDCC","key":"#E3DBCA","line":"#D3C9B5","track":"#E6DFD0","text":"#2A2925","muted":"#6E695D","faint":"#A29C8E","accent":"#0F766E","accent2":"#1D4ED8","kind":"#BE185D","up":"#15803D","warning":"#B45309","down":"#B91C1C","unknown":"#8B8678"},"font":{"family":"SF Mono","size":12}}"##
        guard case .failure(.refused(let p)) = ThemeStore.load(Data(paper.utf8)) else { Issue.record("accepted"); return }
        #expect(p.map(\.description) == ["warning and down differ by ΔE 9.1, under 15", "warning and unknown differ by ΔE 14.6, under 15"])
    }

    @Test func refusesWithReasons() {
        let gray = ##"{"schema":1,"id":"x","renderer":"cells","tokens":{"ink":"#000000","inkHigh":"#000000","selection":"#000000","key":"#000000","line":"#000000","track":"#000000","text":"#222222","muted":"#000000","faint":"#000000","accent":"#000000","accent2":"#000000","kind":"#000000","up":"#808080","warning":"#828282","down":"#ff0000","unknown":"#00ff00"}}"##
        guard case .failure(.refused(let p)) = ThemeStore.load(Data(gray.utf8)) else { Issue.record("accepted"); return }
        #expect(p.contains { $0.description.hasPrefix("text on ink") })
        #expect(p.contains { $0.description.hasPrefix("up and warning differ") })
        guard case .failure(.refused(let missing)) = ThemeStore.load(Data(#"{"schema":1,"id":"y","renderer":"cells","tokens":{}}"#.utf8)) else { Issue.record("accepted"); return }
        #expect(missing.count == TokenSlots.cells.count)
        guard case .failure(.unreadable) = ThemeStore.load(Data("{}".utf8)) else { Issue.record("accepted"); return }
    }

    @Test func colorMath() {
        #expect(RGBA(css: "#0A1016") == RGBA(10 / 255, 16 / 255, 22 / 255))
        #expect(RGBA(css: "rgba(255, 0, 0, .5)") == RGBA(1, 0, 0, 0.5))
        #expect(RGBA(css: "#fff")?.r == 1)
        #expect(RGBA(css: "nope") == nil)
        #expect(abs(ThemeValidator.contrast(RGBA(0, 0, 0), RGBA(1, 1, 1)) - 21) < 0.01)
        #expect(ThemeValidator.deltaE(RGBA(1, 0, 0), RGBA(1, 0, 0)) == 0)
        #expect(ThemeValidator.deltaE(RGBA(0, 0, 0), RGBA(1, 1, 1)) > 99)
    }

    @Test func userThemesAreOffButTheLoaderWorks() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(ThemeStore.terminalJSON.replacingOccurrences(of: "\"terminal\"", with: "\"mine\"").utf8).write(to: dir.appending(path: "mine.json"))
        try Data("{".utf8).write(to: dir.appending(path: "broken.json"))
        var off = ThemeStore()
        off.loadUserThemes(from: dir)
        #expect(off.themes == ThemeStore.builtIn)
        var on = ThemeStore()
        on.loadUserThemes(from: dir, enabled: true)
        #expect(on.themes.map(\.id) == ThemeStore.builtIn.map(\.id) + ["mine"])
        #expect(on.refused.map(\.file) == ["broken.json"])
        #expect(on.theme("nope").id == "native")
    }

}
