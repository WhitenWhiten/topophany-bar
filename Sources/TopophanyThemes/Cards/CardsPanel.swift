import LocalReadings
import SwiftUI
import TopophanySections

/// The Native look: the panel as cards on glass.
struct CardsPanel: View {
    var model: PanelModel
    var ctx: RenderContext
    @Environment(\.panelActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollHeight: Double = 0

    var p: CardsPalette { CardsPalette.resolve(ctx) }
    var t: CardsType { CardsType(scale: ctx.scale, theme: ctx.theme) }

    /// Between cards; ruled sections meet at their rules.
    var gap: Double { p.style.surface == .matte ? 0 : 6 }

    var body: some View {
        let p = self.p
        VStack(spacing: gap) {
            CardsHeader(chrome: model.chrome, p: p, t: t)
            if model.pinStatus, ctx.maxHeight != nil {
                CardsStatusCard(status: model.status, alert: model.alert, p: p, t: t)
                scrolling(p)
            } else {
                CardsStatusCard(status: model.status, alert: model.alert, p: p, t: t)
                sections(p)
            }
            CardsFooter(chrome: model.chrome, p: p, t: t)
        }
        .padding(8)
        .frame(width: 344 * ctx.scale)
        .background { CardsPanelBackground(ctx: ctx, p: p, radius: p.style.panelRadius) }
        .environment(\.colorScheme, ctx.effectiveScheme)
    }

    @ViewBuilder
    func sections(_ p: CardsPalette) -> some View {
        ForEach(model.sections) { s in
            CardsSection(section: s, ctx: ctx, p: p, t: t)
        }
    }

    /// Status stays pinned; the rest scrolls when the panel would be taller
    /// than the screen allows, and brings the keyboard's focus into view.
    func scrolling(_ p: CardsPalette) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: gap) { sections(p) }
                    .onGeometryChange(for: Double.self) { $0.size.height } action: { scrollHeight = $0 }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(scrollHeight, max(120, (ctx.maxHeight ?? .infinity) - 230 * ctx.scale)))
            .onChange(of: ctx.focus) { _, focus in
                guard let focus else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo(focus) }
            }
        }
    }
}

/// What the panel sits on: glass, as the system draws it; a matte ground
/// and its texture; or a night that deepens toward the foot.
struct CardsPanelBackground: View {
    var ctx: RenderContext
    var p: CardsPalette
    var radius: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            CardsGround(p: p, live: ctx.backdrop == .live && !ctx.reduceTransparency, shape: shape)
            shape.strokeBorder(p.isDark ? Color.white.opacity(ctx.increaseContrast ? 0.45 : 0.2) : Color.white.opacity(0.75),
                               lineWidth: 0.5)
        }
        .overlay(shape.stroke(p.isDark ? Color.black.opacity(0.75) : Color.black.opacity(ctx.increaseContrast ? 0.4 : 0.14),
                              lineWidth: 0.5))
    }
}

/// A surface's ground, in `shape`: the panel's, or a widget's.
struct CardsGround<S: Shape>: View {
    var p: CardsPalette
    /// Real glass behind it, rather than a drawn fill.
    var live: Bool
    var shape: S

    var body: some View {
        switch p.style.surface {
        case .glass:
            if live { shape.fill(.clear).glassEffect(.regular.tint(p.panel), in: shape) } else { shape.fill(p.panel) }
        case .matte:
            shape.fill(p.panel)
        case .night:
            shape.fill(LinearGradient(colors: [p.panel, p.panel2 ?? p.panel], startPoint: .top, endPoint: .bottom))
        }
        if p.style.texture != .none { TextureFill(texture: p.style.texture, color: p.grain).clipShape(shape) }
    }
}

// MARK: chrome

struct CardsHeader: View {
    var chrome: PanelChrome
    var p: CardsPalette
    var t: CardsType
    @Environment(\.panelActions) private var actions

    var body: some View {
        HStack(spacing: 9) {
            BrandMark()
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text("Topophany").font(t.font(13.5, .semibold)).foregroundStyle(p.l1)
                Text(Words.join([chrome.project, chrome.view]))
                    .font(t.font(11)).foregroundStyle(p.l2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HeaderButton(symbol: "apple.terminal", label: tr("Open in Terminal"), shortcut: "o", p: p) { actions.openTerminal() }
            HeaderButton(symbol: "gearshape", label: tr("Settings"), shortcut: ",", p: p) { actions.openSettings() }
        }
        .padding(EdgeInsets(top: 3, leading: 5, bottom: 1, trailing: 3))
    }
}

struct HeaderButton: View {
    var symbol: String
    var label: String
    var shortcut: KeyEquivalent
    var p: CardsPalette
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(hover ? p.l1 : p.l2)
                .frame(width: 26, height: 26)
                .background(Circle().fill(p.fill2).opacity(hover ? 1 : 0))
                .contentShape(Circle())
                .animation(Highlight.easing(hover), value: hover)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
        .keyboardShortcut(shortcut, modifiers: .command)
    }
}

/// Quiets the menu bar's alert until it gets worse, and shows that it is
/// quiet: pressed, in the accent, until clicked again.
struct QuietButton: View {
    var quiet: Bool
    var p: CardsPalette
    var t: CardsType
    @Environment(\.panelActions) private var actions
    @State private var hover = false

    var body: some View {
        Button { actions.toggleQuiet() } label: {
            HStack(spacing: 4) {
                Image(systemName: quiet ? "bell.slash.fill" : "bell.slash").font(.system(size: 10 * t.scale, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(quiet ? tr("Quieted") : tr("Quiet"))
            }
            .font(t.font(11, .medium))
            .foregroundStyle(quiet ? p.accent : hover ? p.l1 : p.l2)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 3.5)
            .background(Capsule().fill(quiet ? p.accent.opacity(hover ? 0.24 : 0.16) : hover ? p.fill : p.fill2))
            .contentShape(Capsule())
            .animation(Highlight.easing(hover), value: hover)
            .animation(.easeOut(duration: 0.2), value: quiet)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .help(quiet ? tr("The menu bar stays quiet until this gets worse. Click to show its colors again.")
                    : tr("Quiet the menu bar until this gets worse"))
        .accessibilityLabel(quiet ? tr("Show the menu bar’s colors again") : tr("Quiet the menu bar until this gets worse"))
    }
}

struct CardsFooter: View {
    var chrome: PanelChrome
    var p: CardsPalette
    var t: CardsType
    @Environment(\.panelActions) private var actions

    var body: some View {
        HStack {
            let color: Color = chrome.isLive ? p.up : (chrome.connection == .starting ? p.unknown : p.down)
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 6, height: 6)
                    .background(Circle().fill(color.opacity(0.22)).frame(width: 12, height: 12))
                Text(chrome.connectionText).lineLimit(1)
            }
            .font(t.font(11)).foregroundStyle(p.l3)
            .accessibilityElement(children: .combine)
            Spacer()
            Button { actions.quit() } label: {
                Text(tr("Quit")).font(t.font(11.5, .medium)).foregroundStyle(p.l1)
                    .padding(.horizontal, 11).padding(.vertical, 3)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: p.style.radius(7), style: .continuous)
                        if p.style.surface == .glass { shape.fill(p.fill2) } else { shape.strokeBorder(p.cardEdge, lineWidth: 0.75) }
                    }
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(EdgeInsets(top: 1, leading: 8, bottom: 0, trailing: 4))
    }
}

// MARK: cards

/// A section: a card on glass, outlined at night, or on matte a ruled
/// block of the page, its rule above it.
struct Card<Content: View>: View {
    var p: CardsPalette
    var padding = EdgeInsets(top: 8, leading: 11, bottom: 9, trailing: 11)
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: p.style.cardRadius, style: .continuous)
        let matte = p.style.surface == .matte
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(matte ? EdgeInsets(top: padding.top + 3, leading: 6, bottom: padding.bottom + 3, trailing: 6) : padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if matte {
                    if let tint { Rectangle().fill(tint.opacity(0.5)).frame(height: 2).frame(maxHeight: .infinity, alignment: .top) }
                } else {
                    shape.fill(p.card)
                    if let tint {
                        shape.fill(LinearGradient(stops: [.init(color: tint, location: 0), .init(color: .clear, location: 0.55)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay {
                if matte {
                    Rectangle().fill(p.cardEdge).frame(height: 0.75).frame(maxHeight: .infinity, alignment: .top)
                } else {
                    shape.strokeBorder(p.cardEdge, lineWidth: p.style.surface == .night ? 0.75 : 0.5)
                }
            }
    }
}

struct CardTitle: View {
    var symbol: String
    var title: String
    var meta: String
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        HStack(spacing: 6) {
            if p.style.caps {
                // Small capitals, as a printed page titles its sections.
                Text(title.uppercased(with: L10n.locale)).font(t.font(10, .semibold)).tracking(1.4).foregroundStyle(p.accent)
            } else {
                Image(systemName: symbol).font(.system(size: 11.5 * t.scale, weight: .medium)).frame(width: 14)
                Text(title).font(t.font(11.5, .semibold))
            }
            Spacer(minLength: 6)
            Text(meta).font(t.font(p.style.caps ? 10.5 : 11, .medium)).foregroundStyle(p.l3).lineLimit(1)
        }
        .foregroundStyle(p.l2)
        .padding(.bottom, p.style.caps ? 8 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: status

struct CardsStatusCard: View {
    var status: StatusSection
    var alert: MenuBarAlert = .unavailable
    var p: CardsPalette
    var t: CardsType

    var tint: Color? {
        switch status.mark {
        case .down: p.down.opacity(0.13)
        case .degraded: p.warn.opacity(0.12)
        case .up: p.up.opacity(0.10)
        default: nil
        }
    }

    var body: some View {
        Card(p: p, padding: EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12), tint: tint) {
            HStack(spacing: 12) {
                HeroSymbol(status: status, size: 44, palette: p)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(status.title).font(t.font(19, .semibold)).tracking(-0.34).foregroundStyle(p.l1).lineLimit(1)
                            .contentTransition(.numericText()).settles(on: status.title)
                        if alert != .unavailable {
                            Spacer(minLength: 0)
                            QuietButton(quiet: alert == .quiet, p: p, t: t)
                        }
                    }
                    Text(status.subtitle).font(t.font(12)).foregroundStyle(p.l2).lineLimit(2)
                }
            }
            .padding(.bottom, 12)
            // The words read as one; the Quiet button stays a button.
            .accessibilityElement(children: alert == .unavailable ? .combine : .contain)
            if status.isBlind {
                cached
            } else if let c = status.counts?.complete {
                StackBar(counts: c, palette: p).padding(.bottom, 8)
                    .accessibilityLabel(tr("\(c.up) up, \(c.warning) warn, \(c.down) down, \(c.unknown) unknown"))
                legend(c)
            }
            meta
        }
    }

    var cached: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            PillView(pill: .cached, palette: p, type: t)
            Text(emphasized(status.history, p.l1)).font(t.font(12)).foregroundStyle(p.l2).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func legend(_ c: (up: Int, warning: Int, down: Int, unknown: Int)) -> some View {
        HStack(spacing: 13) {
            item(c.up, .up, tr("up"))
            item(c.warning, .degraded, tr("warn"))
            item(c.down, .down, tr("down"))
            item(c.unknown, .unknown, tr("unknown"))
        }
        .font(t.font(11)).foregroundStyle(p.l2)
        .accessibilityHidden(true)
    }

    func item(_ n: Int, _ m: Mark, _ word: String) -> some View {
        HStack(spacing: 4) {
            CardMark(mark: m, size: 9, color: p.color(m)).opacity(n == 0 ? 0.45 : 1)
            Text("\(n)").font(t.mono(11, .semibold)).foregroundStyle(n == 0 ? p.l3 : p.l1)
                .contentTransition(.numericText(value: Double(n))).settles(on: n)
            Text(word).foregroundStyle(n == 0 ? p.l3 : p.l2)
        }
    }

    var meta: some View {
        VStack(spacing: 0) {
            Rectangle().fill(p.sep).frame(height: 0.5).padding(.top, 9)
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "target").font(.system(size: 10 * t.scale))
                    if let live = status.observersLive, let all = status.observersAll, !status.isBlind {
                        Text(tr("\(live)/\(all) observers live"))
                    } else {
                        Text(tr("Observers not known now"))
                    }
                }
                Spacer()
                if let at = status.isBlind ? status.lastKnown?.at : status.updatedAt {
                    Text(tr("Updated \(Words.ago(at, now: status.now))"))
                }
            }
            .font(t.font(11)).foregroundStyle(p.l3)
            .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: sections

struct CardsSection: View {
    var section: PanelModel.Section
    var ctx: RenderContext
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        switch section {
        case .seen(let s): CardsSeen(seen: s, p: p, t: t, focus: ctx.focus)
        case .attention(let a): CardsAttention(attention: a, p: p, t: t, focus: ctx.focus)
        case .applications(let a): CardsApplications(apps: a, p: p, t: t, focus: ctx.focus)
        case .fleet(let f): CardsFleet(fleet: f, p: p, t: t)
        case .servers(let cards):
            Card(p: p) {
                CardTitle(symbol: "server.rack", title: tr("Servers"), meta: tr("\(cards.count) pinned"), p: p, t: t)
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Rectangle().fill(p.sep).frame(height: 0.5).padding(.vertical, 10) }
                    CardsServer(card: c, p: p, t: t, focused: ctx.focus == "server:" + c.id)
                }
            }
        case .zones(let z):
            CardsZones(zones: z, p: p, t: t)
        case .mac(.server(let c, let node)):
            Card(p: p) {
                CardTitle(symbol: macSymbol(c.name), title: tr("This Mac"), meta: tr("as a server · \(node)"), p: p, t: t)
                CardsServer(card: c, symbol: macSymbol(c.name), p: p, t: t, focused: ctx.focus == "server:" + c.id)
                if let o = c.observes.first {
                    VStack(spacing: 0) {
                        Rectangle().fill(p.sep).frame(height: 0.5).padding(.top, 8)
                        HStack(spacing: 6) {
                            Image(systemName: "target").font(.system(size: 11 * t.scale))
                            Text(tr("Observes from here"))
                            Spacer()
                            CardMark(mark: o.mark, size: 10, color: p.color(o.mark))
                            Text(o.text).fontWeight(.medium).foregroundStyle(p.l1)
                        }
                        .font(t.font(11.5)).foregroundStyle(p.l2).padding(.top, 8)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        case .mac(.local(let l)):
            CardsLocal(local: l, p: p, t: t)
        }
    }
}

struct FocusRing: ViewModifier {
    var on: Bool
    var p: CardsPalette

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: p.style.radius(7), style: .continuous).fill(p.accent.opacity(0.16)).padding(.horizontal, -5)
                    .opacity(on ? 1 : 0)
                    .animation(Highlight.easing(on), value: on)
            }
    }
}

/// A row that opens something lights faintly under the pointer, as far
/// out as the keyboard's focus does.
struct HoverRow: ViewModifier {
    var p: CardsPalette
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: p.style.radius(7), style: .continuous).fill(p.fill2).padding(.horizontal, -5)
                    .opacity(hover ? 1 : 0)
                    .animation(Highlight.easing(hover), value: hover)
            }
            .onHover { hover = $0 }
    }
}

struct CardsSeen: View {
    var seen: SeenFromSection
    var p: CardsPalette
    var t: CardsType
    var focus: String?

    var body: some View {
        Card(p: p) {
            CardTitle(symbol: "target", title: tr("Seen from"), meta: seen.total.map { tr("\($0) observers") } ?? "", p: p, t: t)
            FlowLayout(spacing: 5) {
                if let problems = seen.problems {
                    if problems.isEmpty {
                        chip(.up, tr("All \(seen.calm) observers report no problem"), nil, calm: true, focused: false)
                    } else {
                        ForEach(problems) { o in chip(o.mark, o.name, o.note, calm: false, focused: focus == "seen:" + o.id) }
                        if seen.calm > 0 { chip(.up, tr("\(seen.calm) others report no problem"), nil, calm: true, focused: false) }
                    }
                } else {
                    chip(.offline, tr("Not known while offline"), nil, calm: false, focused: false)
                }
            }
        }
        // A scroll can't find a chip inside the flow, so the card stands
        // in for the one focused.
        .background { if let focus, focus.hasPrefix("seen:") { Color.clear.id(focus) } }
    }

    func chip(_ m: Mark, _ name: String, _ note: String?, calm: Bool, focused: Bool) -> some View {
        HStack(spacing: 5) {
            CardMark(mark: m, size: calm ? 10 : 11, color: p.color(m))
            Text(name).foregroundStyle(calm ? p.l2 : p.l1)
            if let note { Text(note).font(t.font(11)).foregroundStyle(p.l2) }
        }
        .font(t.font(11.5))
        .lineLimit(1)
        .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 8))
        .background {
            let shape = RoundedRectangle(cornerRadius: p.style.chip(7), style: .continuous)
            if calm {
                shape.strokeBorder(p.isDark ? p.sep : Color.black.opacity(0.12), lineWidth: 0.5)
            } else {
                shape.fill(m == .unknown || m == .offline ? p.unknown.opacity(0.18) : p.color(m).opacity(0.15))
            }
            shape.strokeBorder(p.accent, lineWidth: 1.5).opacity(focused ? 1 : 0).animation(Highlight.easing(focused), value: focused)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CardsAttention: View {
    var attention: AttentionSection
    var p: CardsPalette
    var t: CardsType
    var focus: String?
    @Environment(\.panelActions) private var actions

    var body: some View {
        Card(p: p) {
            CardTitle(symbol: "exclamationmark.triangle", title: tr("Needs attention"), meta: "\(attention.total)", p: p, t: t)
            ForEach(Array(attention.items.enumerated()), id: \.element.id) { i, a in
                if i > 0 { Rectangle().fill(p.sep).frame(height: 0.5) }
                row(a)
                    .padding(.top, i == 0 ? 1 : 5.5).padding(.bottom, 5.5)
                    .modifier(HoverRow(p: p))
                    .modifier(FocusRing(on: focus == "attention:" + a.id, p: p))
                    .id("attention:" + a.id)
            }
            if attention.more > 0 {
                Rectangle().fill(p.sep).frame(height: 0.5)
                Button { actions.openAttention(nil) } label: {
                    HStack(spacing: 2) {
                        Text(tr("\(attention.more) more in Topophany"))
                        Image(systemName: "chevron.right").font(.system(size: 9 * t.scale, weight: .semibold))
                    }
                    .font(t.font(11.5, .medium)).foregroundStyle(p.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .modifier(HoverRow(p: p))
                .modifier(FocusRing(on: focus == "attention:more", p: p))
                .id("attention:more")
                .padding(.top, 4)
            }
        }
    }

    func row(_ a: AttentionSection.Item) -> some View {
        Button { actions.openAttention(a) } label: {
            HStack(spacing: 9) {
                CardMark(mark: a.mark, size: 14, color: p.color(a.mark)).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    RouteLine(route: a.route, arrow: p.l3).font(t.font(12.5, .medium)).foregroundStyle(p.l1)
                    Text(subtitle(a)).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PillView(pill: a.pill, palette: p, type: t, plain: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
    }

    func subtitle(_ a: AttentionSection.Item) -> String {
        Words.join([Words.kind(a.kind), a.observerName.isEmpty ? "" : tr("from \(a.observerName)"),
                    a.since.map { Words.span(since: $0, now: attention.now) } ?? ""])
    }
}

struct CardsApplications: View {
    var apps: ApplicationsSection
    var p: CardsPalette
    var t: CardsType
    var focus: String?

    var body: some View {
        Card(p: p) {
            CardTitle(symbol: "square.3.layers.3d", title: tr("Applications"),
                      meta: tr("\(apps.serviceCount) services in \(apps.rows.count)"), p: p, t: t)
            ForEach(apps.rows) { a in
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        CardMark(mark: a.mark, size: 10, color: p.color(a.mark))
                        Text(a.name).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 3) {
                        ForEach(Array(a.services.prefix(8).enumerated()), id: \.offset) { _, m in
                            CardMark(mark: m, size: 8, color: p.color(m))
                        }
                    }
                    .frame(width: 70 * t.scale, alignment: .leading)
                    Text(a.note)
                        .font(t.font(11, a.noteNeedsLook ? .semibold : .regular))
                        .foregroundStyle(a.noteNeedsLook ? p.l1 : p.l3)
                        .lineLimit(1)
                        .frame(width: 96 * t.scale, alignment: .trailing)
                }
                .font(t.font(12.5)).foregroundStyle(p.l1)
                .padding(.vertical, 2.5)
                .opacity(apps.isCurrent ? 1 : 0.55)
                .modifier(FocusRing(on: focus == "app:" + a.id, p: p))
                .id("app:" + a.id)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct CardsServer: View {
    var card: ServerCardModel
    /// A symbol of its own, such as This Mac's model; otherwise its
    /// provider's logo stands for it.
    var symbol: String?
    var p: CardsPalette
    var t: CardsType
    var focused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                NodeAvatar(provider: card.provider, kind: card.kind, size: 28, p: p, symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.name).font(t.font(12.5, .semibold)).foregroundStyle(p.l1).lineLimit(1)
                    // The time where it is never gives way; the provider, in
                    // the middle, does first.
                    HStack(spacing: 0) {
                        Text(card.isMissing ? card.place : card.subtitle).lineLimit(1).truncationMode(.middle)
                        if !card.isMissing, let time = card.localTime { Text(verbatim: " · " + time).fixedSize() }
                    }
                    .font(t.font(11)).foregroundStyle(p.l2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PillView(pill: card.pill, palette: p, type: t)
            }
            .accessibilityElement(children: .combine)
            HStack(alignment: .top, spacing: 10) {
                meter(tr("CPU"), card.cpu)
                meter(tr("Memory"), card.memory)
                meter(tr("Disk"), card.disk)
            }
            .padding(.top, 10).padding(.bottom, 7)
            HStack {
                Text(card.servicesSummary).lineLimit(1)
                Spacer(minLength: 8)
                Text(card.age).lineLimit(1)
            }
            .font(t.font(10.5)).foregroundStyle(p.l3)
        }
        .modifier(FocusRing(on: focused, p: p))
        .id("server:" + card.id)
    }

    func meter(_ label: String, _ m: ServerCardModel.Meter) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(t.font(10.5)).foregroundStyle(p.l2)
                Spacer(minLength: 2)
                HStack(spacing: 3) {
                    if m.isOverLimit { CardMark(mark: .degraded, size: 9, color: p.warn) }
                    Text(m.percent.map { Words.percent($0, digits: 0) } ?? "—")
                        .font(t.mono(12, .semibold)).foregroundStyle(p.l1)
                        .contentTransition(.numericText(value: m.percent ?? 0)).settles(on: m.percent)
                }
            }
            Meter(percent: m.percent, limit: m.limit, palette: p)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.percent.map { "\(label) \(Words.percent($0, digits: 0))" } ?? "\(label) \(tr("unknown"))")
    }
}

// MARK: time zones

struct CardsZones: View {
    var zones: ZonesSection
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        Card(p: p) {
            CardTitle(symbol: "clock", title: tr("Time zones"),
                      meta: Words.join([tr("\(zones.zones.count) zones"), tr("\(zones.serverCount) servers")]), p: p, t: t)
            // One grid, so every ribbon is as wide as the others and the now
            // ticks line up.
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(zones.zones.enumerated()), id: \.element.id) { i, z in
                    if i > 0 { Rectangle().fill(p.sep).frame(height: 0.5).gridCellUnsizedAxes(.horizontal) }
                    GridRow {
                        time(z)
                        middle(z).padding(.horizontal, 10)
                        right(z).gridColumnAlignment(.trailing)
                    }
                    .padding(.top, i == 0 ? 1 : 4.5).padding(.bottom, 4.5)
                }
            }
            if zones.unplaced > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(p.sep).frame(height: 0.5).padding(.top, 2)
                    Text(tr("\(zones.unplaced) without a time zone")).font(t.font(10.5)).foregroundStyle(p.l3).padding(.top, 6)
                }
            }
        }
    }

    func time(_ z: ZonesSection.Zone) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(z.time).font(t.mono(15, .semibold)).tracking(-0.15).foregroundStyle(p.l1)
                .contentTransition(.numericText()).settles(on: z.time)
            Text(Words.join([z.period, z.zoneName])).font(t.font(10, .medium)).foregroundStyle(p.l3).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Words.join([z.title, z.clock, z.zoneName, z.relative, z.day, tr("\(z.servers.count) servers")]))
    }

    func middle(_ z: ZonesSection.Zone) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if z.isHere {
                    Image(systemName: "location.fill").font(.system(size: 9 * t.scale)).foregroundStyle(p.accent)
                }
                Text(z.title).font(t.font(12)).foregroundStyle(p.l1).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                // Cut short, trouble first, so trouble left out still shows.
                let servers = z.servers.count > 8 ? Mark.troubleFirst(z.servers, by: \.mark) : z.servers
                HStack(spacing: 2.5) {
                    ForEach(Array(servers.prefix(8).enumerated()), id: \.offset) { _, s in
                        CardMark(mark: s.mark, size: 8, color: p.color(s.mark))
                    }
                    if z.servers.count > 8 {
                        Text("+\(z.servers.count - 8)").font(t.font(10)).foregroundStyle(p.l3).padding(.leading, 2)
                    }
                }
                .fixedSize()
            }
            DayRibbon(zone: z, dark: p.isDark, now: p.accent, contrast: p.increaseContrast)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    func right(_ z: ZonesSection.Zone) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(z.relative).font(t.mono(11, .medium)).foregroundStyle(z.isHere ? p.l2 : p.l3)
            if !z.day.isEmpty { Text(z.day).font(t.font(10)).foregroundStyle(p.l3) }
        }
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: 28, alignment: .trailing)
        .accessibilityHidden(true)
    }
}

/// A zone's day from 12 hours before now to 12 hours after: a fine band,
/// slate around its midnight and pale around its noon, a gap at midnight,
/// and now a tick in the accent, in the middle, where every zone's now
/// lines up. Neither tone is a status color.
struct DayRibbon: View {
    var zone: ZonesSection.Zone
    var dark: Bool
    var now: Color
    var contrast = false
    var band = 4.0

    /// Night and day, as red, green, blue and opacity.
    var tones: (night: [Double], day: [Double]) {
        dark ? ([0.42, 0.49, 0.72, contrast ? 0.42 : 0.26], [0.97, 0.96, 0.93, contrast ? 0.75 : 0.5])
            : ([0.2, 0.25, 0.42, contrast ? 0.62 : 0.44], [0.24, 0.24, 0.3, contrast ? 0.16 : 0.08])
    }

    var body: some View {
        let (night, noon) = tones
        let stops = (0...48).map { i -> Gradient.Stop in
            let b = ZonesSection.daylight(ZonesSection.hour(zone, at: Double(i) / 48))
            let c = zip(night, noon).map { $0 + ($1 - $0) * b }
            return .init(color: Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: c[3]), location: Double(i) / 48)
        }
        let tick = RoundedRectangle(cornerRadius: 1)
        // Shapes and fills only: a widget's drawing is kept as views, and
        // a layer clipped inside a canvas doesn't survive it.
        RibbonBand(band: band, midnights: ZonesSection.midnights(zone))
            .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
            .overlay {
                tick.fill(now)
                    .background(RoundedRectangle(cornerRadius: 2).fill(dark ? Color.black.opacity(0.4) : Color.white.opacity(0.9))
                        .padding(-1))
                    .frame(width: 2)
            }
            // The tick overhangs the band; only the band takes room.
            .frame(height: band + 6)
            .padding(.vertical, -3)
    }
}

/// The ribbon's band: as tall as `band`, centred, its ends round, with a
/// gap where midnight falls.
struct RibbonBand: Shape {
    var band: Double
    var midnights: [Double]

    func path(in r: CGRect) -> Path {
        let b = CGRect(x: r.minX, y: r.midY - band / 2, width: r.width, height: band)
        var gaps = Path()
        for m in midnights { gaps.addRect(CGRect(x: r.minX + r.width * m - 0.75, y: r.minY, width: 1.5, height: r.height)) }
        return Path(roundedRect: b, cornerRadius: band / 2).subtracting(gaps)
    }
}

// MARK: this Mac

struct CardsLocal: View {
    var local: LocalSection
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        Card(p: p) {
            CardTitle(symbol: macSymbol(local.model), title: tr("This Mac"),
                      meta: Words.join([local.model, tr("local readings")]), p: p, t: t)
            let tiles = Array(tilesList.enumerated())
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(0..<((tiles.count + 1) / 2), id: \.self) { r in
                    GridRow {
                        tiles[r * 2].element
                        if r * 2 + 1 < tiles.count { tiles[r * 2 + 1].element } else { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                    }
                }
            }
            if let b = local.battery {
                HStack(spacing: 7) {
                    Image(systemName: batterySymbol(b)).font(.system(size: 15 * t.scale))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(p.up)
                    Text("\(b.percent)%").font(t.mono(11.5, .semibold)).foregroundStyle(p.l1)
                    Text(Words.join([local.batteryState, local.batteryRemaining]))
                }
                .font(t.font(11.5)).foregroundStyle(p.l2)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: p.style.surface == .matte ? 3 : 9, style: .continuous).fill(p.fill2))
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }

    var tilesList: [AnyView] {
        var out: [AnyView] = []
        if let c = local.cpu {
            let peak = max(25, (local.cpuHistory.max() ?? 0) * 1.2)
            out.append(AnyView(tile("cpu", tr("CPU"), Words.percent(c.total),
                                    BarHistory(values: local.cpuHistory, top: peak, capacity: LocalSnapshot.historyLength,
                                               color: p.accent, baseline: p.fill, style: p.style.meter),
                                    tr("System \(Words.percent(c.system)) · User \(Words.percent(c.user))"))))
        }
        if let m = local.memory {
            let app = Words.gb(Int64(m.appBytes))
            let foot = m.pressurePercent.map { tr("Pressure \(Words.percent($0, digits: 0)) · App \(app) GB") } ?? tr("App \(app) GB")
            // App, wired and compressed, as Activity Monitor splits "Memory Used".
            let parts = PartsBar(parts: [(Double(m.appBytes), p.accent), (Double(m.wiredBytes), p.accent.opacity(0.6)),
                                         (Double(m.compressedBytes), p.accent.opacity(0.34))],
                                 total: Double(m.totalBytes), track: p.fill, style: p.style.meter, scale: p.l3)
                .help(tr("App \(app) GB · Wired \(Words.gb(Int64(m.wiredBytes))) GB · Compressed \(Words.gb(Int64(m.compressedBytes))) GB"))
            out.append(AnyView(tile("memorychip", tr("Memory"), Words.percent(m.usedPercent), parts, foot)))
        }
        if let s = local.storage {
            out.append(AnyView(tile("internaldrive", tr("Storage"), Words.percent(s.usedPercent),
                                    Meter(percent: s.usedPercent, limit: nil, palette: p, height: 7, plain: true),
                                    tr("\(Words.gb(s.usedBytes)) of \(Words.gb(s.totalBytes)) GB used"))))
        }
        if let n = local.network {
            let sparks = MirrorChart(up: local.receivedHistory, down: local.sentHistory, upColor: p.accent, downColor: p.accent2,
                                     axis: p.sep)
            var foot = AttributedString("↓")
            foot.foregroundColor = p.accent
            foot.font = t.font(10, .bold)
            foot += AttributedString(" \(Words.rateNumber(n.receivedPerSecond)) · ")
            var up = AttributedString("↑")
            up.foregroundColor = p.accent2
            up.font = t.font(10, .bold)
            foot += up + AttributedString(" \(Words.rate(n.sentPerSecond))")
            out.append(AnyView(tile("arrow.up.arrow.down", tr("Network"), n.displayName, sparks, foot, valueIsName: true)))
        }
        return out
    }

    func tile(_ symbol: String, _ label: String, _ value: String, _ graph: some View, _ foot: String, valueIsName: Bool = false) -> some View {
        tile(symbol, label, value, graph, AttributedString(foot), valueIsName: valueIsName)
    }

    func tile(_ symbol: String, _ label: String, _ value: String, _ graph: some View, _ foot: AttributedString,
              valueIsName: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: symbol).font(.system(size: 10.5 * t.scale)).frame(width: 13)
                    Text(label)
                }
                .font(t.font(11)).foregroundStyle(p.l2)
                Spacer(minLength: 4)
                Text(value)
                    .font(valueIsName ? t.font(11, .medium) : t.mono(13, .semibold))
                    .foregroundStyle(valueIsName ? p.l2 : p.l1)
                    .lineLimit(1)
            }
            graph.frame(height: 22).frame(maxWidth: .infinity).padding(.top, 5).padding(.bottom, 3)
            Text(foot).font(t.font(10)).foregroundStyle(p.l3).lineLimit(1)
        }
        .padding(EdgeInsets(top: 7, leading: 8, bottom: 6, trailing: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: p.style.surface == .matte ? 3 : 9, style: .continuous)
            switch p.style.surface {
            case .glass: shape.fill(p.fill2)
            case .night: shape.strokeBorder(p.cardEdge, lineWidth: 0.75)
            case .matte: shape.fill(p.fill2.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }

    func batterySymbol(_ b: BatteryReading) -> String {
        let level = b.percent >= 88 ? 100 : b.percent >= 63 ? 75 : b.percent >= 38 ? 50 : b.percent >= 13 ? 25 : 0
        return b.state == .charging ? "battery.100percent.bolt" : "battery.\(level)percent"
    }
}
