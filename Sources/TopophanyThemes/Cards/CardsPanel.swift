import LocalReadings
import SwiftUI
import TopophanySections

/// The Native look: the panel as cards on glass.
struct CardsPanel: View {
    var model: PanelModel
    var ctx: RenderContext
    @Environment(\.panelActions) private var actions
    @State private var scrollHeight: Double = 0

    var p: CardsPalette { CardsPalette.resolve(ctx) }
    var t: CardsType { CardsType(scale: ctx.scale) }

    nonisolated static let radius = 18.0

    var body: some View {
        let p = self.p
        VStack(spacing: 7) {
            CardsHeader(chrome: model.chrome, p: p, t: t)
            if model.pinStatus, ctx.maxHeight != nil {
                CardsStatusCard(status: model.status, p: p, t: t)
                scrolling(p)
            } else {
                CardsStatusCard(status: model.status, p: p, t: t)
                sections(p)
            }
            CardsFooter(chrome: model.chrome, p: p, t: t)
        }
        .padding(8)
        .frame(width: 344 * ctx.scale)
        .background { CardsPanelBackground(ctx: ctx, p: p, radius: Self.radius) }
        .environment(\.colorScheme, ctx.effectiveScheme)
    }

    @ViewBuilder
    func sections(_ p: CardsPalette) -> some View {
        ForEach(model.sections) { s in
            CardsSection(section: s, ctx: ctx, p: p, t: t)
        }
    }

    /// Status stays pinned; the rest scrolls when the panel would be taller
    /// than the screen allows.
    func scrolling(_ p: CardsPalette) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 7) { sections(p) }
                .onGeometryChange(for: Double.self) { $0.size.height } action: { scrollHeight = $0 }
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(scrollHeight, max(120, (ctx.maxHeight ?? .infinity) - 230 * ctx.scale)))
    }
}

struct CardsPanelBackground: View {
    var ctx: RenderContext
    var p: CardsPalette
    var radius: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if ctx.backdrop == .live, !ctx.reduceTransparency {
                shape.fill(.clear).glassEffect(.regular.tint(p.panel), in: shape)
            } else {
                shape.fill(p.panel)
            }
            shape.strokeBorder(p.isDark ? Color.white.opacity(ctx.increaseContrast ? 0.45 : 0.2) : Color.white.opacity(0.75),
                               lineWidth: 0.5)
        }
        .overlay(shape.stroke(p.isDark ? Color.black.opacity(0.75) : Color.black.opacity(ctx.increaseContrast ? 0.4 : 0.14),
                              lineWidth: 0.5))
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
                .background(Circle().fill(hover ? p.fill2 : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
        .keyboardShortcut(shortcut, modifiers: .command)
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
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.fill2))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(EdgeInsets(top: 1, leading: 8, bottom: 0, trailing: 4))
    }
}

// MARK: cards

struct Card<Content: View>: View {
    var p: CardsPalette
    var padding = EdgeInsets(top: 9, leading: 11, bottom: 10, trailing: 11)
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(p.card)
                if let tint {
                    shape.fill(LinearGradient(stops: [.init(color: tint, location: 0), .init(color: .clear, location: 0.55)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay(shape.strokeBorder(p.cardEdge, lineWidth: 0.5))
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
            Image(systemName: symbol).font(.system(size: 11.5 * t.scale, weight: .medium)).frame(width: 14)
            Text(title).font(t.font(11.5, .semibold))
            Spacer(minLength: 6)
            Text(meta).font(t.font(11, .medium)).foregroundStyle(p.l3).lineLimit(1)
        }
        .foregroundStyle(p.l2)
        .padding(.bottom, 7)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: status

struct CardsStatusCard: View {
    var status: StatusSection
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
                    Text(status.title).font(t.font(19, .semibold)).tracking(-0.34).foregroundStyle(p.l1).lineLimit(1)
                    Text(status.subtitle).font(t.font(12)).foregroundStyle(p.l2).lineLimit(2)
                }
            }
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
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
        case .servers(let cards):
            Card(p: p) {
                CardTitle(symbol: "server.rack", title: tr("Servers"), meta: tr("\(cards.count) pinned"), p: p, t: t)
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Rectangle().fill(p.sep).frame(height: 0.5).padding(.vertical, 10) }
                    CardsServer(card: c, symbol: "server.rack", p: p, t: t, focused: ctx.focus == "server:" + c.id)
                }
            }
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
                if on {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.accent.opacity(0.16)).padding(.horizontal, -5)
                }
            }
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
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            if calm {
                shape.strokeBorder(p.isDark ? p.sep : Color.black.opacity(0.12), lineWidth: 0.5)
            } else {
                shape.fill(m == .unknown || m == .offline ? p.unknown.opacity(0.18) : p.color(m).opacity(0.15))
            }
            if focused { shape.strokeBorder(p.accent, lineWidth: 1.5) }
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
                    .padding(.top, i == 0 ? 1 : 6.5).padding(.bottom, 6.5)
                    .modifier(FocusRing(on: focus == "attention:" + a.id, p: p))
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
                    .padding(.top, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(FocusRing(on: focus == "attention:more", p: p))
            }
        }
    }

    func row(_ a: AttentionSection.Item) -> some View {
        Button { actions.openAttention(a) } label: {
            HStack(spacing: 9) {
                CardMark(mark: a.mark, size: 14, color: p.color(a.mark)).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(routeText(a.route, arrow: p.l3)).font(t.font(12.5, .medium)).foregroundStyle(p.l1)
                        .lineLimit(1).truncationMode(.tail)
                    Text(subtitle(a)).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PillView(pill: a.pill, palette: p, type: t)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .padding(.vertical, 3.1)
                .opacity(apps.isCurrent ? 1 : 0.55)
                .modifier(FocusRing(on: focus == "app:" + a.id, p: p))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct CardsServer: View {
    var card: ServerCardModel
    var symbol: String
    var p: CardsPalette
    var t: CardsType
    var focused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 13 * t.scale)).foregroundStyle(p.l2)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.fill2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.name).font(t.font(12.5, .semibold)).foregroundStyle(p.l1).lineLimit(1)
                    Text(card.isMissing ? card.place : card.subtitle).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1)
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
                }
            }
            Meter(percent: m.percent, limit: m.limit, palette: p)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.percent.map { "\(label) \(Words.percent($0, digits: 0))" } ?? "\(label) \(tr("unknown"))")
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
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
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
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.fill2))
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
                                    Sparkline(values: local.cpuHistory, top: peak, color: p.accent),
                                    tr("System \(Words.percent(c.system)) · User \(Words.percent(c.user))"))))
        }
        if let m = local.memory {
            let app = Words.gb(Int64(m.appBytes))
            let foot = m.pressurePercent.map { tr("Pressure \(Words.percent($0, digits: 0)) · App \(app) GB") } ?? tr("App \(app) GB")
            out.append(AnyView(tile("memorychip", tr("Memory"), Words.percent(m.usedPercent),
                                    Meter(percent: m.usedPercent, limit: nil, palette: p, height: 7, plain: true), foot)))
        }
        if let s = local.storage {
            out.append(AnyView(tile("internaldrive", tr("Storage"), Words.percent(s.usedPercent),
                                    Meter(percent: s.usedPercent, limit: nil, palette: p, height: 7, plain: true),
                                    tr("\(Words.gb(s.usedBytes)) of \(Words.gb(s.totalBytes)) GB used"))))
        }
        if let n = local.network {
            let sparks = ZStack {
                Sparkline(values: local.receivedHistory, top: nil, color: p.accent)
                Sparkline(values: local.sentHistory, top: nil, color: p.accent2)
            }
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
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.fill2))
        .accessibilityElement(children: .combine)
    }

    func batterySymbol(_ b: BatteryReading) -> String {
        let level = b.percent >= 88 ? 100 : b.percent >= 63 ? 75 : b.percent >= 38 ? 50 : b.percent >= 13 ? 25 : 0
        return b.state == .charging ? "battery.100percent.bolt" : "battery.\(level)percent"
    }
}
