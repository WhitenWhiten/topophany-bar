import LocalReadings
import SwiftUI
import TopophanyKit
import TopophanySections

/// How Glance lays a panel out. Status and Seen from are one card, the
/// hero, always first. Then, in the order Settings gives the sections:
/// Needs attention and each pinned list, open; Map, Fleet and Time zones
/// as one card, where the first of them stands; and every other section
/// open while something in it asks for a look, else a line among its calm
/// neighbours. State decides what opens, never where a section stands, so
/// nothing changes places while the panel is read, and ↑ ↓ keep to what's
/// drawn.
struct GlanceLayout: Equatable {
    enum Part: Equatable, Identifiable {
        /// A section open as a card.
        case card(PanelModel.Section)
        /// Map, Fleet and Time zones, those shown, in the panel's order.
        case places([PanelModel.Section])
        /// Calm sections next to each other, a line each.
        case lines([PanelModel.Section])

        var id: String {
            switch self {
            case .card(let s): "card:" + s.id.rawValue
            case .places: "places"
            case .lines(let s): "lines:" + (s.first?.id.rawValue ?? "")
            }
        }
    }

    var seen: SeenFromSection?
    var parts: [Part]

    init(_ model: PanelModel) {
        var seen: SeenFromSection?
        var parts: [Part] = []
        var run: [PanelModel.Section] = []
        var places: [PanelModel.Section] = []
        var placesAt: Int?
        func flush() {
            if !run.isEmpty { parts.append(.lines(run)) }
            run = []
        }
        for s in model.sections {
            switch s {
            case .seen(let x):
                seen = x
            case .map, .fleet, .zones:
                if placesAt == nil {
                    flush()
                    placesAt = parts.count
                    parts.append(.places([]))
                }
                places.append(s)
            case .attention, .services, .servers:
                flush()
                parts.append(.card(s))
            case .applications, .mac:
                if Self.asksForLook(s) {
                    flush()
                    parts.append(.card(s))
                } else {
                    run.append(s)
                }
            }
        }
        flush()
        if let i = placesAt { parts[i] = .places(places) }
        self.seen = seen
        self.parts = parts
    }

    /// Down or warn: what opens a section. Unknown isn't trouble, nor is it
    /// calm; a line shows it by its mark.
    static func isTrouble(_ m: Mark) -> Bool { m == .down || m == .degraded }

    /// Whether something in a section asks for a look: a mark in trouble,
    /// or a note that says so ("3 attention"). This Mac's own readings
    /// carry no health, so they never do.
    static func asksForLook(_ s: PanelModel.Section) -> Bool {
        switch s {
        case .applications(let a): a.isCurrent && a.rows.contains { $0.noteNeedsLook || isTrouble($0.mark) }
        case .mac(.server(let c, _)): isTrouble(c.mark)
        default: false
        }
    }

    /// The keyboard's stops as drawn: the hero's observers, then each part.
    var focusOrder: [String] {
        var ids = (seen?.problems ?? []).map { "seen:" + $0.id }
        for part in parts {
            switch part {
            case .card(let s): ids += Renderers.focusStops(s)
            case .places(let s), .lines(let s): ids += s.flatMap(Renderers.focusStops)
            }
        }
        return ids
    }
}

/// The panel as Glance lays it out (`GlanceLayout`): Native's header,
/// footer, glass and scrolling, the hero pinned as Status is.
struct GlancePanel: View {
    var model: PanelModel
    var ctx: RenderContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollHeight: Double = 0
    /// The panel's height, and the scroll's within it, as last laid out.
    @State private var panelHeight: Double?
    @State private var scrollFrame: Double = 0
    @State private var leapState = PanelScrollState()
    /// The calm lines a click opened. They stay open while the app runs,
    /// as the places' lens stays chosen; the keyboard's focus opens a line
    /// only while it's there.
    @State private var opened: Set<SectionID>

    /// `opened`: the lines open to begin with, as clicks would leave them.
    init(model: PanelModel, ctx: RenderContext, opened: Set<SectionID> = []) {
        self.model = model
        self.ctx = ctx
        _opened = State(initialValue: opened)
    }

    var p: CardsPalette { CardsPalette.resolve(ctx) }
    var t: CardsType { CardsType(scale: ctx.scale, theme: ctx.theme) }

    static let gap = 6.0

    /// The most the scroll shows at once: what the panel's height leaves
    /// it.
    var scrollLimit: Double {
        // Everything else: header, footer, gaps, padding, and the hero when
        // pinned.
        let fixed = panelHeight.map { $0 - scrollFrame } ?? (model.pinStatus ? 250 : 82) * ctx.scale
        return max(120, (ctx.maxHeight ?? .infinity) - fixed)
    }

    /// Whether the sections scroll: there's more of them than shows.
    var scrolls: Bool { ctx.maxHeight != nil && scrollHeight > scrollLimit }

    var body: some View {
        #if DEBUG
        let _ = PanelDiagnostics.count("glance.body")
        #endif
        let p = self.p
        let layout = GlanceLayout(model)
        VStack(spacing: Self.gap) {
            CardsHeader(chrome: model.chrome, p: p, t: t)
            if ctx.maxHeight != nil {
                if model.pinStatus { hero(layout, p) }
                scrolling(layout, p)
            } else {
                hero(layout, p)
                parts(layout, p)
            }
            CardsFooter(chrome: model.chrome, p: p, t: t, scrollState: scrolls ? leapState : nil, leap: leap)
        }
        .padding(8)
        .onGeometryChange(for: Double.self) { $0.size.height } action: { panelHeight = $0 }
        .frame(width: 344 * ctx.scale)
        .background { CardsPanelBackground(ctx: ctx, p: p, radius: p.style.panelRadius) }
        .environment(\.colorScheme, ctx.effectiveScheme)
    }

    func hero(_ layout: GlanceLayout, _ p: CardsPalette) -> some View {
        GlanceHero(status: model.status, seen: layout.seen, alert: model.alert, download: model.download, p: p, t: t,
                   focus: ctx.focus.flatMap { $0.hasPrefix("seen:") ? $0 : nil })
            .equatable()
    }

    @ViewBuilder
    func parts(_ layout: GlanceLayout, _ p: CardsPalette) -> some View {
        ForEach(layout.parts) { part in
            switch part {
            case .card(let s):
                GlanceCard(section: s, p: p, t: t, focus: ctx.focus).equatable()
            case .places(let s):
                GlancePlaces(sections: s, p: p, t: t, mapFocused: ctx.focus == "map").equatable()
            case .lines(let s):
                GlanceLines(sections: s, opened: opened.intersection(s.map(\.id)), p: p, t: t, focus: ctx.focus, toggle: toggle)
                    .equatable()
            }
        }
    }

    func toggle(_ id: SectionID) {
        if opened.contains(id) { opened.remove(id) } else { opened.insert(id) }
    }

    /// The sections scroll when the panel would be taller than it may be,
    /// beneath the hero when it's pinned and with it otherwise, and bring
    /// the keyboard's focus into view.
    func scrolling(_ layout: GlanceLayout, _ p: CardsPalette) -> some View {
        PanelScroller(state: leapState, height: min(scrollHeight, scrollLimit), panelHeight: ctx.maxHeight ?? 0,
                      focus: ctx.focus, leaps: ctx.leaps) {
            VStack(spacing: Self.gap) {
                if !model.pinStatus { hero(layout, p) }
                parts(layout, p)
            }
            .onGeometryChange(for: Double.self) { $0.size.height } action: { scrollHeight = $0 }
        }
        .onGeometryChange(for: Double.self) { $0.size.height } action: { scrollFrame = $0 }
        .mask { PanelScrollFade(state: leapState, enabled: scrolls) }
    }

    /// About half the panel down, or from the end back to the top.
    func leap() {
        guard scrolls, let panel = ctx.maxHeight else { return }
        leapState.leap(panel: panel, reduceMotion: reduceMotion)
    }
}

// MARK: the hero

/// Status and Seen from as one card: the verdict, larger than Native's;
/// every check on the bar, and at its trouble end what needs a look,
/// counted; who sees a problem; then the observers and the age, as Native's
/// foot has them.
struct GlanceHero: View, Equatable {
    var status: StatusSection
    var seen: SeenFromSection?
    var alert: MenuBarAlert
    var download: TopoOffer?
    var p: CardsPalette
    var t: CardsType
    /// The observer the keyboard is on.
    var focus: String?

    var body: some View {
        // Native's card for the same verdict, for the parts drawn alike.
        let native = CardsStatusCard(status: status, alert: alert, download: download, p: p, t: t)
        Card(p: p, padding: EdgeInsets(top: 13, leading: 13, bottom: 10, trailing: 13), tint: native.tint) {
            HStack(spacing: 13) {
                HeroSymbol(status: status, size: 50, palette: p)
                VerdictLines {
                    Text(status.title).font(t.font(23, .bold)).tracking(-0.55).foregroundStyle(p.l1)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .contentTransition(.numericText()).settles(on: status.title)
                    Text(download?.line ?? status.subtitle).font(t.font(12)).foregroundStyle(p.l2).lineLimit(2)
                    if let coverage = status.coverageText {
                        Text(coverage).font(t.font(11)).monospacedDigit()
                            .foregroundStyle(status.coverageIsComplete ? p.l3 : p.l2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                            .help(status.coverageHelp ?? "")
                    }
                    if alert != .unavailable || download != nil {
                        HStack(spacing: 8) {
                            if alert != .unavailable { QuietButton(quiet: alert == .quiet, p: p, t: t) }
                            if let download { DownloadButton(offer: download, p: p, t: t) }
                        }
                        .layoutValue(key: VerdictLines.Action.self, value: true)
                    }
                }
            }
            .padding(.bottom, 13)
            // The words read as one; a button stays a button.
            .accessibilityElement(children: alert == .unavailable && download == nil ? .combine : .contain)
            if let sources = status.sources {
                CardsSourceRows(sources: sources, p: p, t: t)
            } else if status.isBlind {
                native.cached
            } else if let c = status.counts?.complete {
                GlanceCheckBar(counts: c, p: p, t: t)
            }
            if let seen, status.sources == nil {
                GlanceSeen(seen: seen, p: p, t: t, focus: focus).padding(.top, 13)
            }
            if let notice = status.notice {
                Text(notice).font(t.font(11)).foregroundStyle(p.l2).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            native.meta
        }
        // A scroll can't find a chip inside the flow, so the card stands
        // in for the one focused.
        .background { if let focus { Color.clear.id(focus) } }
    }
}

/// Every check on Native's bar, and at its trouble end what needs a look,
/// a count beside each mark: one figure where Native's legend has four.
/// While nothing does, the checks that pass.
struct GlanceCheckBar: View {
    var counts: (up: Int, warning: Int, down: Int, unknown: Int)
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        let c = counts
        HStack(spacing: 10) {
            StackBar(counts: c, palette: p)
            GlanceCounts(counts: c, p: p, t: t)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("\(c.up) up, \(c.warning) warn, \(c.down) down, \(c.unknown) unknown"))
    }
}

/// What needs a look, counted beside its marks: warn, down, unknown, each
/// while there are any; while nothing does, the checks that pass.
struct GlanceCounts: View {
    var counts: (up: Int, warning: Int, down: Int, unknown: Int)
    var p: CardsPalette
    var t: CardsType

    struct Count: Identifiable {
        var mark: Mark
        var n: Int
        var id: Mark { mark }
    }

    var shown: [Count] {
        let trouble = [Count(mark: .degraded, n: counts.warning), Count(mark: .down, n: counts.down),
                       Count(mark: .unknown, n: counts.unknown)].filter { $0.n > 0 }
        return trouble.isEmpty ? [Count(mark: .up, n: counts.up)] : trouble
    }

    var body: some View {
        HStack(spacing: 9) {
            ForEach(shown) { s in
                HStack(spacing: 3.5) {
                    CardMark(mark: s.mark, size: 10, color: s.mark == .up ? p.calmUp : p.color(s.mark))
                    Text("\(s.n)").font(t.mono(13.5, .semibold)).foregroundStyle(s.mark == .up ? p.l2 : p.l1)
                        .contentTransition(.numericText(value: Double(s.n))).settles(on: s.n)
                }
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Who sees a problem, as Native's chips, and how many others report none;
/// while none do, one line that says so.
struct GlanceSeen: View {
    var seen: SeenFromSection
    var p: CardsPalette
    var t: CardsType
    var focus: String?

    var body: some View {
        if let problems = seen.problems, !problems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                label
                FlowLayout(spacing: 5) {
                    ForEach(problems) { o in
                        SeenChip(mark: o.mark, name: o.name, note: o.note, calm: false, focused: focus == "seen:" + o.id, p: p, t: t)
                    }
                    if seen.calm > 0 {
                        SeenChip(mark: .up, name: tr("\(seen.calm) others report no problem"), note: nil, calm: true,
                                 focused: false, p: p, t: t)
                    }
                }
            }
        } else {
            let calm = seen.problems != nil
            // Beside the label while it fits, else beneath it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { label; line(calm) }.fixedSize()
                VStack(alignment: .leading, spacing: 5) { label; line(calm) }
            }
            .accessibilityElement(children: .combine)
        }
    }

    var label: some View {
        Text(tr("Seen from")).font(t.font(11, .semibold)).foregroundStyle(p.l3)
            .accessibilityAddTraits(.isHeader)
    }

    func line(_ calm: Bool) -> some View {
        HStack(spacing: 5) {
            CardMark(mark: calm ? .up : .offline, size: 9, color: calm ? p.calmUp : p.unknown)
            Text(calm ? tr("All \(seen.calm) observers report no problem") : tr("Not known while offline"))
                .font(t.font(11.5)).foregroundStyle(p.l2).lineLimit(1)
        }
    }
}

// MARK: cards and lines

/// A section open as a card: Native's, but a pinned list as tiles.
struct GlanceCard: View, Equatable {
    var section: PanelModel.Section
    var p: CardsPalette
    var t: CardsType
    var focus: String?

    var body: some View {
        switch section {
        case .services(let cards):
            GlancePinned(title: cards.contains { $0.monitor != nil } ? tr("Pinned") : tr("Services"),
                         meta: tr("\(cards.count) pinned items"), items: cards.map { .service($0) }, p: p, t: t, focus: focus)
        case .servers(let cards):
            GlancePinned(title: tr("Servers"), meta: tr("\(cards.count) pinned"), items: cards.map { .server($0) },
                         p: p, t: t, focus: focus)
        default:
            CardsSection(section: section, p: p, t: t, focus: focus)
        }
    }
}

/// Calm sections next to each other, a line each in one card.
struct GlanceLines: View, Equatable {
    var sections: [PanelModel.Section]
    /// Those a click opened.
    var opened: Set<SectionID>
    var p: CardsPalette
    var t: CardsType
    var focus: String?
    var toggle: @MainActor (SectionID) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sections == rhs.sections && lhs.opened == rhs.opened && lhs.p == rhs.p && lhs.t == rhs.t && lhs.focus == rhs.focus
    }

    var body: some View {
        Card(p: p, padding: EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 11)) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Rectangle().fill(p.sep).frame(height: 0.5) }
                let open = opened.contains(s.id) || Self.holds(s, focus)
                GlanceLine(section: s, open: open, p: p, t: t, focus: open ? focus : nil) { toggle(s.id) }
                    .equatable()
            }
        }
    }

    /// Whether the keyboard's focus is on a row inside `s`.
    static func holds(_ s: PanelModel.Section, _ focus: String?) -> Bool {
        guard let focus else { return false }
        return Renderers.focusStops(s).contains(focus)
    }
}

/// A calm section as a line: its title, what it comes to, and a chevron
/// that turns as it opens; open, the section beneath it, as its card has
/// it.
struct GlanceLine: View, Equatable {
    var section: PanelModel.Section
    var open: Bool
    var p: CardsPalette
    var t: CardsType
    /// The keyboard's focus, while the line is open.
    var focus: String?
    var toggle: @MainActor () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.section == rhs.section && lhs.open == rhs.open && lhs.p == rhs.p && lhs.t == rhs.t && lhs.focus == rhs.focus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Text(title).font(t.font(12.5, .semibold)).foregroundStyle(p.l1).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    summary
                    Image(systemName: "chevron.right").font(.system(size: 9.5 * t.scale, weight: .semibold)).foregroundStyle(p.l3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.vertical, 9.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .modifier(HoverRow(p: p))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Words.join([title, spoken])))
            .accessibilityValue(Text(open ? tr("Expanded") : tr("Collapsed")))
            .accessibilityAddTraits(.isButton)
            if open {
                VStack(alignment: .leading, spacing: 7) {
                    if !caption.isEmpty { Text(caption).font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1) }
                    content
                }
                .padding(.bottom, 11)
            }
        }
    }

    var title: String {
        switch section {
        case .applications: tr("Applications")
        case .mac: tr("This Mac")
        // Only Applications and This Mac fold into a line.
        default: ""
        }
    }

    /// What the section comes to: a mark for each application, or a few
    /// readings, fewer where they don't fit.
    @ViewBuilder var summary: some View {
        switch section {
        case .applications(let a):
            HStack(spacing: 8) {
                FittedText(choices: [tr("\(a.serviceCount) services in \(a.rows.count)"), ""])
                    .font(t.font(11.5)).foregroundStyle(p.l3)
                marks(a)
            }
        case .mac(.local(let l)):
            FittedText(choices: Self.readings(l)).font(t.font(11.5)).foregroundStyle(p.l2)
        case .mac(.server(let c, _)):
            HStack(spacing: 5) {
                CardMark(mark: c.mark, size: 9, color: p.listColor(c.mark))
                FittedText(choices: Self.meters(c)).font(t.font(11.5)).foregroundStyle(p.l2)
            }
        default:
            EmptyView()
        }
    }

    /// An application's mark each, trouble first where some are left out.
    func marks(_ a: ApplicationsSection) -> some View {
        let rows = a.rows.count > 8 ? Mark.troubleFirst(a.rows, by: \.mark) : a.rows
        return HStack(spacing: 3) {
            ForEach(rows.prefix(8)) { r in CardMark(mark: r.mark, size: 9, color: p.listColor(r.mark)) }
            if rows.count > 8 { Text(verbatim: "+\(rows.count - 8)").font(t.font(10.5)).foregroundStyle(p.l3).padding(.leading, 1) }
        }
        .fixedSize()
        .opacity(a.isCurrent ? 1 : 0.55)
    }

    /// What VoiceOver hears for the summary.
    var spoken: String {
        switch section {
        case .applications(let a):
            Words.join([tr("\(a.serviceCount) services in \(a.rows.count)")] + a.rows.map { Words.join([$0.name, $0.note]) })
        case .mac(.local(let l)): Self.readings(l).first ?? ""
        case .mac(.server(let c, _)): Words.join([c.mark.word, Self.meters(c).first ?? ""])
        default: ""
        }
    }

    /// Above the section, open: what its card's title says beside it.
    var caption: String {
        switch section {
        case .mac(.local(let l)): Words.join([l.model, tr("local readings")])
        case .mac(.server(_, let node)): tr("as a server · \(node)")
        default: ""
        }
    }

    @ViewBuilder var content: some View {
        switch section {
        case .applications(let a): ApplicationRows(apps: a, p: p, t: t, focus: focus)
        case .mac(.local(let l)): LocalTiles(local: l, p: p, t: t)
        case .mac(.server(let c, _)): MacServer(card: c, p: p, t: t, focused: focus == "server:" + c.id)
        default: EmptyView()
        }
    }

    /// This Mac's readings in a line, "CPU 17% · Memory 72% · Storage 44%",
    /// and shorter. They carry no health, so no mark.
    static func readings(_ l: LocalSection) -> [String] {
        var parts: [String] = []
        if let c = l.cpu { parts.append(tr("CPU") + " " + Words.percent(c.total, digits: 0)) }
        if let m = l.memory { parts.append(tr("Memory") + " " + Words.percent(m.usedPercent, digits: 0)) }
        if let s = l.storage { parts.append(tr("Storage") + " " + Words.percent(s.usedPercent, digits: 0)) }
        return FittedText.choices(parts: parts.joined(separator: " · "))
    }

    /// A server's meters in a line, "CPU 12% · Memory 40% · Disk 55%", and
    /// shorter; withheld, how old its last reading is.
    static func meters(_ c: ServerCardModel) -> [String] {
        if c.isWithheld || c.hasNoCurrentSample { return [c.age] }
        let parts = [(tr("CPU"), c.cpu), (tr("Memory"), c.memory), (tr("Disk"), c.disk)].compactMap { label, m in
            m.percent.map { label + " " + Words.percent($0, digits: 0) }
        }
        return FittedText.choices(parts: parts.joined(separator: " · "))
    }
}
