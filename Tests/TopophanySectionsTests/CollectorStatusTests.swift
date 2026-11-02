import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

@Suite struct CollectorStatusTests {
    @Test func acquisitionIsNotBusinessHealth() throws {
        try L10n.with("en") {
            let now = Date()
            let read = try JSONDecoder().decode(CollectorRead.self, from: Data(#"{"state":"error","stage":"tcp","code":"tcp_timeout","consecutive_failures":2}"#.utf8))
            var source = CollectorStatus(name: "S2", read: read, isCurrent: true, now: now)
            #expect(source.summary == "Retrying")
            #expect(source.detail.contains("tcp_timeout"))
            source.refreshing = true
            #expect(source.summary == "Updating")
            source.refreshing = false; source.isCurrent = false
            #expect(source.summary == "Data expired")
            let unavailable = StatusSection(kind: .blind(.collectorUnreachable), mark: .offline, now: now)
            let expired = StatusSection(kind: .blind(.leaseLapsed), mark: .offline, now: now)
            let stopped = StatusSection(kind: .blind(.engineStopped(restartAt: nil)), mark: .offline, now: now)
            #expect(Set([unavailable.title, expired.title, stopped.title]).count == 3)
            #expect(unavailable.mark == .offline && unavailable.count == nil)
            var waiting = unavailable
            source.isCurrent = true; source.read.state = "waiting"
            waiting.collector = source
            #expect(waiting.title == "Waiting for data")
            #expect(waiting.subtitle == "Reading collector…")
            #expect(waiting.shortSubtitle == waiting.subtitle)
            #expect(StatusItemModel(status: waiting, appearance: .init()).activity == .connecting)

            var updating = expired
            source.isCurrent = false; source.read.state = "ok"; source.refreshing = true
            updating.collector = source
            #expect(updating.isBlind && updating.count == nil)
            #expect(updating.title == "Updating")
            #expect(updating.subtitle == "Reading collector…")
            #expect(updating.shortSubtitle == updating.subtitle)
            #expect(StatusItemModel(status: updating, appearance: .init()).activity == .connecting)
            updating.collector?.refreshing = false
            #expect(updating.title == expired.title)
        }
    }
}
