import Foundation
import Testing
import TopophanyKit
@testable import TopophanySections

/// Synthetic `check.card` and `service.card` rows shaped like Topophany's
/// stream values: invented names, documentation addresses, example domains.
enum MonitorFixtures {
    static let generated = "2026-11-01T07:37:46Z"
    static let sampled = "2026-11-01T07:37:40Z"
    static let until = "2026-11-01T07:38:01Z"
    static let now = Timestamp.parse(generated)!

    static func slots(_ ms: Int, tail: [String] = [], count: Int = 12) -> [[String: Any]] {
        (0..<count).map { i in
            i >= count - tail.count ? ["outcome": tail[i - (count - tail.count)]] : ["outcome": "ok", "elapsed_ms": ms]
        }
    }

    /// A check value; `diagnostic` is omitted when `nil`.
    static func check(_ id: String, kind: String = "http", health: String = "up", diagnostic: [String: Any]?,
                      observer: (id: String, name: String) = ("obs-mac", "Seattle MacBook"), p50: Int = 40,
                      tail: [String] = [], colo: String = "", firstByte: String = "") -> [String: Any] {
        var c: [String: Any] = [
            "id": id, "name": id, "kind": kind, "endpoint": "", "health": health, "freshness": "fresh",
            "sampled_at": sampled, "valid_until": until, "latency": ["p50_ms": p50, "p95_ms": p50 + p50 / 4],
            "up_24h": 99.5, "first_byte": firstByte, "colo": colo,
            "samples": ["interval_seconds": 15, "slots": slots(p50, tail: tail)],
            "observer": ["id": observer.id, "name": observer.name], "reason": "",
        ]
        if let diagnostic { c["diagnostic"] = diagnostic }
        return c
    }

    static func row(_ metric: String, select: [String: String], health: String = "up", _ value: Any) -> [String: Any] {
        ["id": metric + ":" + (select.values.first ?? ""), "label": "", "metric": metric, "select": select, "visual": "card",
         "text": "", "health": health, "freshness": "fresh", "sampled_at": sampled, "valid_until": until, "value": value]
    }

    static func reading(_ rows: [[String: Any]]) throws -> Reading {
        let frame: [String: Any] = [
            "schema": 1, "name": "stream", "request_id": "fixture", "config_revision": "fixture-1", "instance": "fixture",
            "sequence": 1, "source": "preview", "project": "preview-homelab", "lifecycle": "running",
            "generated_at": generated, "publisher_expires_at": "2026-11-01T07:38:16Z", "title": "Topophany", "bar_row": "status",
            "rows": rows,
        ]
        let f = try #require(FrameDecoder.frame(from: JSONSerialization.data(withJSONObject: frame)))
        var policy = ReaderPolicy(); policy.receive(f, at: now)
        return policy.evaluate(at: now)
    }

    /// The pinned card for one synthetic check.
    static func card(_ check: [String: Any], expanded: Bool = true) throws -> ServiceCardModel {
        let id = try #require(check["id"] as? String)
        let pin = MonitorPin(kind: .check, id: id)
        let r = try reading([row("check.card", select: ["check": id], health: check["health"] as? String ?? "up", check)])
        return try #require(SectionBuilder.monitors(r, pins: [pin], expanded: expanded ? [pin] : []).first)
    }

    static func monitor(_ check: [String: Any]) throws -> MonitorCardModel {
        try #require(try card(check).monitor)
    }

    static func field(_ m: MonitorCardModel, _ label: String) -> String? {
        m.checks.first?.fields.first { $0.label == label }?.value
    }
}
