import SwiftUI
import Testing
import TopophanyEngine
import TopophanyKit
import TopophanySections
@testable import TopophanyThemes

/// A card for each state the previews show, as `topo` would send it:
/// built from a `service.card` row, so the section builder words it.
enum ServiceStates {
    static func slots(_ p50: Double, failing: Int = 0, outcome: ServiceCard.Slot.Outcome = .fail, seed: Int = 1) -> [ServiceCard.Slot] {
        (0..<36).map { i in
            if i >= 36 - failing { return .init(outcome) }
            let jitter = 0.84 + 0.34 * Double((i * 37 + seed * 11) % 100) / 100
            return .init(.ok, elapsed: (p50 * jitter).rounded())
        }
    }

    static func check(_ id: String, _ health: Health, p50: Double, up: Double, failing: Int = 0, colo: String? = nil) -> ServiceCard.Check {
        .init(id: id, name: id, kind: "http", endpoint: "web", health: health, freshness: "fresh", sampledAt: snapshotOrigin,
              validUntil: snapshotOrigin.addingTimeInterval(30), latency: .init(p50: p50, p95: p50 * 1.2), up24h: up, colo: colo,
              samples: .init(interval: 10, slots: slots(p50, failing: failing, seed: id.count)))
    }

    static func observer(_ id: String, _ name: String, _ label: String, _ checks: [ServiceCard.Check]) -> ServiceCard.SeenFrom {
        .init(observer: .init(id: id, name: name), label: label, health: checks.first?.health ?? .unknown, checks: checks)
    }

    static let oracleNY = ServiceCard.Host(id: "oracle-ny", name: "Oracle New York", kind: "host", provider: "Oracle", place: "New York",
                                           health: .up)

    /// Exit Candidate A, affected by the path to it: a mark per check,
    /// two observers in one city by their names.
    static let affected = ServiceCard(
        id: "exit-a", name: "Exit Candidate A", application: .init(id: "proxy", name: "Proxy chain"), health: .degraded,
        note: "affected", host: .init(id: "oracle-la", name: "Oracle LA", kind: "host", provider: "Oracle", place: "Los Angeles", health: .up),
        seenFrom: [observer("seattle-windows", "Seattle Windows", "Windows", [check("w-a", .down, p50: 120, up: 99.3, failing: 16),
                                                                              check("w-aux", .up, p50: 386, up: 98.6)]),
                   observer("seattle-macbook", "Seattle MacBook", "MacBook", [check("m-a", .down, p50: 118, up: 97.6, failing: 16),
                                                                              check("m-aux", .up, p50: 389, up: 98.3)])],
        endpoints: [.init(id: "exit", network: "external", address: "https://ip.example.invalid/json", health: .degraded)])

    /// Memos, down from where it is checked.
    static let down = ServiceCard(
        id: "memos", name: "Memos", application: .init(id: "site", name: "Main site"), health: .down, host: oracleNY,
        seenFrom: [observer("seattle-windows", "Seattle Windows", "Seattle", [check("w-memos", .down, p50: 159, up: 98.6, failing: 12)])],
        endpoints: [.init(id: "memos", network: "tailnet", address: "http://100.64.0.61:5230/healthz", health: .down)])

    /// Viewed from one observer: no check of its measures the service;
    /// other observers' do.
    static let elsewhere = ServiceCard(
        id: "vless-entry", name: "VLESS+Reality Entry (Primary)", application: .init(id: "proxy", name: "Proxy chain"), health: .unknown,
        reason: "registered, not monitored", monitored: false, elsewhere: true,
        host: .init(id: "transit", name: "BandwagonHost LA", kind: "host", provider: "bandwagon", place: "Los Angeles", health: .up),
        endpoints: [.init(id: "entry", network: "public", address: "192.0.2.10:443", health: nil)])

    static func card(_ c: ServiceCard) -> ServiceCardModel {
        let row = Row(id: "service-1", metric: "service.card", select: .init(service: c.id), value: .serviceCard(c), health: c.health,
                      validUntil: snapshotOrigin.addingTimeInterval(15))
        var p = ReaderPolicy()
        p.receive(Frame(instance: "s", sequence: 1, generatedAt: snapshotOrigin, publisherExpiresAt: snapshotOrigin.addingTimeInterval(30),
                        rows: [row]), at: snapshotOrigin)
        return SectionBuilder.services(p.evaluate(at: snapshotOrigin.addingTimeInterval(4)), ids: [c.id])[0]
    }
}

@MainActor
@Suite(.serialized) struct ServiceSnapshots {
    init() { L10n.force("en") }

    /// The panel with Applications and the pinned services in view, as
    /// bar.html's: the primary entry failing from two observers, and the
    /// main site up behind Cloudflare.
    func pinned(_ scenario: FixtureEngine.Scenario = .incidents) -> PanelModel {
        var s = previewSettings(mac: .off, services: true)
        s.sections.seen = false
        s.sections.fleet = false
        s.sections.zones = false
        return previewPanel(scenario, settings: s)
    }

    func panel(_ model: PanelModel, theme: Theme, dark: Bool) -> some View {
        let ctx = RenderContext(theme: theme, colorScheme: dark ? .dark : .light)
        return OnDesktop(dark: dark || theme.renderer == .cells) {
            Renderers.renderer(for: theme).panel(model, context: ctx)
        }
    }

    /// A Service widget's model, its card in the panel's Services.
    func widget(_ card: ServiceCardModel?, id: String = "vless-entry") -> WidgetModel {
        var p = previewPanel(.incidents, settings: previewSettings(mac: .off))
        p.sections.append(.services(card.map { [$0] } ?? []))
        return WidgetModel(kind: .service(id: card?.id ?? id), panel: p)
    }

    var fixtureCards: [ServiceCardModel] {
        var s = previewSettings(mac: .off, services: true)
        s.sections.serviceIDs = ["vless-entry", "main-site", "workers-api", "nightly-backup"]
        return previewPanel(.incidents, settings: s).services
    }

    @Test func panels() throws {
        for theme in ThemeStore.builtIn {
            let looks = theme.renderer == .cards ? [true, false] : [theme.id != "paper"]
            for dark in looks {
                try snapshot("service-panel-\(theme.id)-\(dark ? "dark" : "light")", panel(pinned(), theme: theme, dark: dark))
            }
        }
        // Offline, as history; and with the keyboard on the first card.
        try snapshot("service-panel-native-dark-offline", panel(pinned(.offline), theme: ThemeStore.native, dark: true))
        try snapshot("service-panel-terminal-offline", panel(pinned(.offline), theme: ThemeStore.terminal, dark: true))
        var ctx = RenderContext(theme: ThemeStore.terminal, colorScheme: .dark)
        ctx.focus = "service:vless-entry"
        try snapshot("service-panel-terminal-focus", OnDesktop(dark: true) { Renderers.renderer(for: ThemeStore.terminal).panel(pinned(), context: ctx) })
    }

    @Test func widgets() throws {
        let cards = fixtureCards
        let set: [(String, ServiceCardModel)] = [("failing", cards[0]), ("up", cards[1]), ("edge", cards[2])]
        for theme in ThemeStore.builtIn {
            let looks = theme.renderer == .cards ? [true, false] : [theme.id != "paper"]
            for dark in looks {
                let a = theme.renderer == .cards ? "-\(dark ? "dark" : "light")" : ""
                for (name, c) in set {
                    for (size, n) in [(WidgetSize.small, "s"), (.medium, "m")] {
                        try snapshot("service-widget-\(theme.id)\(a)-\(name)-\(n)", onDesktop(widget(c), size, theme: theme, dark: dark))
                    }
                }
            }
        }
        // WidgetKit's smaller sizes, and monochrome.
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for (size, n) in [(WidgetSize.small, "s"), (.medium, "m")] {
                try snapshot("service-widget-\(theme.id)-failing-\(n)-smaller",
                             onDesktop(widget(cards[0]), size, bounds: WidgetSnapshots.smaller[size], theme: theme, dark: true))
                try snapshot("service-widget-\(theme.id)-failing-\(n)-vibrant",
                             onDesktop(widget(cards[0]), size, theme: theme, dark: true, rendering: .vibrant))
            }
        }
    }

    /// The small widget and the panel card in every state: up, affected,
    /// failing from some, down, not monitored, not seen from the observer
    /// viewed from, not current, and not chosen.
    @Test func states() throws {
        let cards = fixtureCards
        let later = snapshotOrigin.addingTimeInterval(47 * 60)
        let states: [(String, ServiceCardModel?)] = [
            ("up", cards[1]), ("affected", ServiceStates.card(ServiceStates.affected)), ("failing", cards[0]),
            ("down", ServiceStates.card(ServiceStates.down)), ("unmonitored", cards[3]),
            ("elsewhere", ServiceStates.card(ServiceStates.elsewhere)), ("not-current", nil), ("unchosen", nil),
        ]
        for theme in [ThemeStore.native, ThemeStore.terminal] {
            for dark in theme.renderer == .cards ? [true, false] : [true] {
                let a = theme.renderer == .cards ? "-\(dark ? "dark" : "light")" : ""
                for (name, c) in states {
                    let model: WidgetModel = switch name {
                    case "not-current": widget(cards[1]).notCurrent(at: later)
                    case "unchosen": widget(nil, id: "")
                    default: widget(c)
                    }
                    try snapshot("service-state-\(theme.id)\(a)-\(name)", onDesktop(model, .small, theme: theme, dark: dark))
                }
            }
        }
        // Each state as the panel draws it.
        var p = pinned()
        p.sections = [.services(states.compactMap(\.1) + [cards[1].withheld(at: later)])]
        try snapshot("service-states-panel-native-dark", panel(p, theme: ThemeStore.native, dark: true))
        try snapshot("service-states-panel-terminal", panel(p, theme: ThemeStore.terminal, dark: true))
    }

    @Test func otherLanguages() throws {
        for l in ["ja", "zh-Hans"] {
            try L10n.with(l) {
                try snapshot("service-panel-native-dark-\(l)", panel(pinned(), theme: ThemeStore.native, dark: true))
                try snapshot("service-panel-terminal-\(l)", panel(pinned(), theme: ThemeStore.terminal, dark: true))
                let c = fixtureCards[1]
                try snapshot("service-widget-native-dark-up-m-\(l)", onDesktop(widget(c), .medium, theme: ThemeStore.native, dark: true))
                try snapshot("service-widget-terminal-up-m-\(l)", onDesktop(widget(c), .medium, theme: ThemeStore.terminal, dark: true))
            }
        }
    }
}
