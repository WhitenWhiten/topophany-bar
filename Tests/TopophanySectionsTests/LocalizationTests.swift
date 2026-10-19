import Foundation
import Testing
@testable import TopophanySections
import TopophanyEngine
import TopophanyKit

/// The catalogs: English plurals, and Japanese and Chinese where the code
/// reads them.
@Suite struct LocalizationTests {
    /// A language the user chose keeps this Mac's region and 12- or 24-hour
    /// choice; a forced one, as tests use, takes its language's own.
    @Test func chosenLanguageKeepsThisMacsClock() {
        let chosen = L10n.locale("ja", keepingThisMac: true)
        #expect(chosen.language.languageCode == "ja")
        #expect(chosen.region == Locale.current.region)
        #expect(chosen.hourCycle == Locale.current.hourCycle)
        let forced = L10n.locale("ja", keepingThisMac: false)
        #expect(forced.identifier == "ja")
    }

    @Test func englishPlurals() {
        L10n.with("en") {
            let s = StatusSection(kind: .verdict(.incidents), mark: .down, topoText: "1 INCIDENT",
                                  counts: HealthCounts(up: 67, warning: 0, down: 1, unknown: 0), configured: 68, incidents: 1,
                                  observersLive: 11, observersAll: 11, updatedAt: origin, lastKnown: nil, now: origin)
            #expect(s.title == "1 incident")
            #expect(s.tuiTitle == "1 INCIDENT")
            #expect(s.subtitle == "1 check down · 67 of 68 passing")
            #expect(s.shortSubtitle == "1 down · 67 of 68 up")
            #expect(tr("\(1) of \(1) checks pass") == "1 of 1 check passes")
            #expect(tr("\(3) of \(3) checks pass") == "3 of 3 checks pass")
            #expect(tr("\(1) checks warning · \(2) incidents") == "1 check warning · 2 incidents")
            #expect(tr("\(3) checks warning · \(1) incidents") == "3 checks warning · 1 incident")
            #expect(tr("\(5) incidents") == "5 incidents")
        }
    }

    @Test func japanese() {
        L10n.with("ja") {
            let p = panel(.incidents)
            #expect(p.status.title == tr("\(5) incidents"))
            #expect(p.status.title != "5 incidents")
            #expect(p.status.title.contains("5"))
            #expect(L10n.previewLanguage == "ja")
            #expect(p.chrome.connectionText == tr("Connected · \("homelab")"))
            #expect(p.chrome.connectionText != "Connected · homelab")
        }
    }

    @Test func chinese() {
        L10n.with("zh-Hans") {
            let p = panel(.clear)
            #expect(p.status.title != "All clear")
            #expect(L10n.previewLanguage == "zh")
            #expect(p.status.subtitle.contains("68"))
        }
    }

    /// The Terminal look's titles, pills and health words are translated
    /// too, not left as the TUI's English.
    @Test func terminalWords() {
        L10n.with("ja") {
            let p = panel(.incidents)
            #expect(p.status.tuiTitle == "インシデント 5 件")
            #expect(Pill.state("open", health: .down).text == "未解決")
            #expect(Pill.health(.up).text == "正常")
            #expect(tr("ALL CLEAR") == "すべて正常")
        }
        L10n.with("zh-Hans") {
            let p = panel(.incidents)
            #expect(p.status.tuiTitle == "5 个事件")
            #expect(Pill.health(.down).text == "故障")
            #expect(p.status.shortSubtitle.hasPrefix("5 项故障"))
        }
    }

    @Test func everyLanguageKeepsTheNumbers() {
        for l in ["en", "ja", "zh-Hans"] {
            L10n.with(l) {
                let p = panel(.degraded)
                #expect(p.status.subtitle.contains("2"), "\(l): \(p.status.subtitle)")
                #expect(p.attention?.total == 2)
            }
        }
    }
}
