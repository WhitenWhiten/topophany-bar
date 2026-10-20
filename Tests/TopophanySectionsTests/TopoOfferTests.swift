import Foundation
import Testing
@testable import TopophanySections
import TopophanyKit

/// The Status card's offer to download `topo`: only while none can run,
/// and in each state of the download.
@Suite struct TopoOfferTests {
    func offer(_ engine: EngineCondition, _ fetch: TopoFetch = .idle) -> TopoOffer? {
        let reading = ReaderPolicy().evaluate(at: origin)
        return SectionBuilder.panel(PanelInput(reading: reading, engine: engine, settings: settings(), fetch: fetch)).download
    }

    @Test func offeredOnlyWhileNoTopoCanRun() {
        L10n.with("en") {
            #expect(offer(.notFound) == TopoOffer(build: .latest, version: nil, state: .ready))
            #expect(offer(.tooOld)?.state == .ready)
            for e in [EngineCondition.starting, .running, .restarting(at: nil), .stopped] {
                #expect(offer(e) == nil)
                #expect(offer(e, .downloading(.latest, version: nil, fraction: nil)) == nil)
            }
        }
    }

    @Test func words() throws {
        try L10n.with("en") {
            let ready = try #require(offer(.notFound))
            #expect(ready.title == "Download topo")
            #expect(ready.line == nil)
            #expect(ready.keyWords == "download topo from its latest release")

            let looking = try #require(offer(.notFound, .downloading(.latest, version: nil, fraction: nil)))
            #expect(looking.title == "Downloading…")
            #expect(looking.line == "Looking for topo’s latest release…")

            let going = try #require(offer(.notFound, .downloading(.latest, version: "1.4.0", fraction: 0.429)))
            #expect(going.title == "Downloading 42%")
            #expect(going.line == "Downloading topo 1.4.0 · 42%")
            #expect(going.keyWords == "downloading topo 1.4.0 · 42%")

            let offline = try #require(offer(.notFound, .failed(next: .latest, .unreachable("The Internet connection appears to be offline."))))
            #expect(offline.title == "Download topo")
            #expect(offline.line == "Couldn’t reach GitHub · try again")
            #expect(offline.keyWords == "couldn’t reach GitHub · try again")

            // The latest couldn't be used: the tested release is offered next.
            let v = TopoBuild.testedVersion
            let unusable = try #require(offer(.tooOld, .failed(next: .tested, .unusable(version: "2.0.0", .upgradeNeeded(path: "/x")))))
            #expect(unusable.title == "Download topo \(v)")
            #expect(unusable.line == "topo 2.0.0 doesn’t speak what this app reads · try \(v), tested with this app")
            #expect(unusable.keyWords == unusable.line)

            let tested = try #require(offer(.notFound, .downloading(.tested, version: nil, fraction: 1)))
            #expect(tested.line == "Downloading topo \(v) · 100%")
        }
    }

    @Test func statusSaysWhatToDo() {
        L10n.with("en") {
            let reading = ReaderPolicy().evaluate(at: origin)
            let missing = SectionBuilder.panel(PanelInput(reading: reading, engine: .notFound, settings: settings()))
            #expect(missing.status.subtitle == "topo not found · download it, or choose one in Settings")
            let old = SectionBuilder.panel(PanelInput(reading: reading, engine: .tooOld, settings: settings()))
            #expect(old.status.subtitle == "This topo has no monitor stream · download a newer one")
        }
    }

    @Test func japaneseAndChinese() throws {
        try L10n.with("ja") {
            #expect(try #require(offer(.notFound)).title == "topo をダウンロード")
            let going = try #require(offer(.notFound, .downloading(.latest, version: "1.4.0", fraction: 0.5)))
            #expect(going.title == "ダウンロード中 50%")
            #expect(going.line == "topo 1.4.0 をダウンロード中 · 50%")
        }
        try L10n.with("zh-Hans") {
            let failed = try #require(offer(.notFound, .failed(next: .latest, .checksumMismatch(version: "1.4.0"))))
            #expect(failed.line == "topo 1.4.0 与其校验和不符，因此未保留 · 请重试")
        }
    }
}
