import SwiftUI
import TopophanySections

// A service's card in the cards renderer: the Server card's head, pill and
// foot, and in place of its meters, a row per observer that sees the
// service. Built from the same pieces, so the two read as one family.

/// Recent samples on one baseline, newest at the right: a passing sample
/// rises as tall as it took, against the slowest shown, at half strength; a
/// failing one hangs below the line in its color, so trouble differs in
/// place as well as color. No sample, no mark. Withheld, the track is
/// hatched; with none held yet, nothing is drawn.
struct ServiceSpark: View {
    var history: ServiceCardModel.History
    /// How many intervals the width holds.
    var count: Int
    var p: CardsPalette
    /// Drawn in one tone: position alone tells a failure from a pass.
    var vibrant = false

    var body: some View {
        switch history {
        case .samples(let samples):
            let shown = Array(samples.suffix(count))
            let p = self.p, count = self.count, vibrant = self.vibrant
            Canvas { ctx, s in
                let base = (s.height * 0.68).rounded()
                let pitch = s.width / Double(count)
                let bw = max(1, pitch - (pitch > 3 ? 1 : 0.6))
                let slowest = max(1, shown.compactMap { if case .ok(let v) = $0 { v } else { nil } }.max() ?? 1)
                ctx.fill(Path(CGRect(x: 0, y: base, width: s.width, height: 1)), with: .color(p.sep))
                for (i, sample) in shown.enumerated() {
                    let x = s.width - Double(shown.count - i) * pitch
                    let rect: CGRect
                    let color: Color
                    switch sample {
                    case .ok(let v):
                        let h = max(1.5, v / slowest * (base - 1))
                        rect = CGRect(x: x, y: base - h, width: bw, height: h)
                        color = vibrant ? p.l1.opacity(0.35) : p.accent.opacity(0.5)
                    case .none:
                        continue
                    case .fail, .policy, .error, .unknown:
                        rect = CGRect(x: x, y: base + 1.5, width: bw, height: s.height - base - 1.5)
                        color = vibrant ? p.l1 : sample == .fail ? p.down : sample == .policy ? p.warn : p.l3
                    }
                    ctx.fill(Path(roundedRect: rect, cornerRadius: min(0.6, bw / 2)), with: .color(color))
                }
            }
        case .withheld:
            Hatch(color: p.fill, line: 1.5, gap: 2.5)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        case .none:
            Color.clear
        }
    }
}

/// A row per observer: a mark per check, its place, the worst check's
/// recent samples, its median over the day and, in the panel, the day's
/// share up.
struct ServiceRows: View {
    var card: ServiceCardModel
    var p: CardsPalette
    var t: CardsType
    var rows = 3
    /// The widget's: smaller marks, a narrower place, the unit set small,
    /// and no share.
    var compact = false
    var vibrant = false

    var body: some View {
        let shown = Array(card.observers.prefix(rows))
        let marks = min(3, shown.map(\.marks.count).max() ?? 1)
        let mark = compact ? 9.0 : 10.0
        VStack(alignment: .leading, spacing: compact ? 6 : 3) {
            if shown.isEmpty, !card.isMissing {
                HStack(alignment: .top, spacing: 7) {
                    CardMark(mark: card.isUnmonitored ? .unknown : .offline, size: 10, color: p.color(.unknown)).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.quiet.title)
                            .font(t.font(11.5)).foregroundStyle(p.l2)
                        if !card.quiet.why.isEmpty { Text(card.quiet.why).font(t.font(11)).foregroundStyle(p.l3) }
                    }
                    .lineLimit(1)
                }
                .padding(.top, 2).padding(.bottom, 4)
            }
            ForEach(shown) { o in
                HStack(spacing: compact ? 4 : 6) {
                    HStack(spacing: 2) {
                        ForEach(Array(o.marks.prefix(marks).enumerated()), id: \.offset) { _, m in
                            CardMark(mark: m, size: mark, color: p.listColor(m))
                        }
                    }
                    .frame(width: Double(marks) * mark + Double(marks - 1) * 2, alignment: .leading)
                    Text(o.label).foregroundStyle(p.l1).lineLimit(1).truncationMode(.tail)
                        .frame(width: compact ? 52 : 64, alignment: .leading)
                    ServiceSpark(history: o.history, count: compact ? 14 : 34, p: p, vibrant: vibrant)
                        .frame(height: compact ? 16 : 18)
                        .frame(maxWidth: .infinity)
                    latency(o.p50)
                        .frame(width: compact ? 34 : 44, alignment: .trailing)
                        .help(o.p95.map { "p95 " + Words.ms($0) } ?? "")
                    if !compact {
                        Text(o.up24h.map(Words.share) ?? "—").font(t.mono(11)).foregroundStyle(p.l3)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .font(t.font(compact ? 11 : 11.5))
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Words.join([o.label, o.marks.first?.word ?? "", o.p50.map(Words.ms) ?? tr("unknown"), o.p95.map { "p95 " + Words.ms($0) } ?? "",
                                                     o.up24h.map { tr("\(Words.share($0)) up in 24 hours") } ?? ""])))
            }
        }
    }

    @ViewBuilder func latency(_ ms: Double?) -> some View {
        if let ms {
            if compact {
                let (number, unit) = Words.latencyParts(ms)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: number).font(t.mono(11, .semibold)).foregroundStyle(p.l1)
                    Text(verbatim: unit).font(t.font(9, .medium)).foregroundStyle(p.l3)
                }
                .fixedSize()
            } else {
                Text(Words.latency(ms)).font(t.mono(11.5, .semibold)).foregroundStyle(p.l1).fixedSize()
            }
        } else {
            Text("—").font(t.mono(11.5, .semibold)).foregroundStyle(p.l3)
        }
    }
}

/// A pinned service in the panel's Services card.
struct CardsService: View {
    var card: ServiceCardModel
    var p: CardsPalette
    var t: CardsType
    var focused = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The Server card's head: its state beside its name.
            HStack(spacing: 9) {
                NodeAvatar(provider: card.host.provider, kind: card.host.kind, size: 28, p: p)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(card.name).font(t.font(12.5, .semibold)).foregroundStyle(p.l1).lineLimit(1)
                        Spacer(minLength: 0)
                        PillView(pill: card.pill, palette: p, type: t)
                    }
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle).font(t.font(11)).foregroundStyle(p.l2).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if !card.memo.isEmpty {
                Text(card.memo).font(t.font(11)).foregroundStyle(p.l3).lineLimit(2).padding(.top, 6)
            }
            if let scope = card.scope { ServiceScope(scope: scope, p: p, t: t).padding(.top, 8) }
            if !card.observers.isEmpty {
                HStack(spacing: 0) {
                    Text(tr("Seen from"))
                    Spacer(minLength: 4)
                    Text(tr("p50")).frame(width: 44, alignment: .trailing)
                    Text(tr("24h")).frame(width: 44, alignment: .trailing)
                }
                .font(t.font(10.5)).foregroundStyle(p.l3)
                .padding(.top, 10).padding(.bottom, 3)
                .accessibilityHidden(true)
            }
            ServiceRows(card: card, p: p, t: t)
                .padding(.top, card.observers.isEmpty ? 10 : 0)
                .padding(.bottom, 8)
            ServiceDiagnoses(card: card, p: p, t: t)
            ServiceDay(card: card, p: p, t: t)
            // Where nothing measures it, the rows say so already; what its
            // checks say beyond their marks is listed above.
            let said = card.isUnmonitored ? "" : card.checksText
            if !said.isEmpty || card.edge != nil || card.runbook != nil || !card.age.isEmpty {
                HStack(spacing: 10) {
                    Text(said).lineLimit(1)
                    Spacer(minLength: 8)
                    if let url = card.runbook {
                        Button { openURL(url) } label: {
                            Label(tr("Runbook"), systemImage: "book").labelStyle(.titleAndIcon).foregroundStyle(p.l2)
                        }
                        .buttonStyle(.plain).fixedSize()
                        .help(url.absoluteString)
                        .accessibilityLabel(Text(tr("Open runbook for \(card.name)")))
                    }
                    if let edge = card.edge { ServiceVia(edge: edge, colos: card.colos, p: p, t: t) }
                    Text(card.age).lineLimit(1)
                }
                .font(t.font(10.5)).foregroundStyle(p.l3)
            }
        }
        .modifier(FocusRing(on: focused, p: p))
        .id("service:" + card.id)
    }
}

/// What its checks say beyond their marks, by observer: up to three, then
/// how many more Topophany shows.
struct ServiceDiagnoses: View {
    var card: ServiceCardModel
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        if !card.diagnoses.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(card.diagnoses.prefix(3)) { d in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        CardMark(mark: d.mark, size: 8, color: p.listColor(d.mark))
                        Text(d.label).foregroundStyle(p.l1).lineLimit(1).fixedSize()
                        Text(d.text).foregroundStyle(p.l2).lineLimit(1).truncationMode(.tail)
                    }
                    .accessibilityElement(children: .combine)
                }
                if card.diagnoses.count > 3 {
                    Text(tr("\(card.diagnoses.count - 3) more in Topophany")).foregroundStyle(p.l3)
                }
            }
            .font(t.font(11))
            .padding(.bottom, 8)
        }
    }
}

/// What topo's assessment adds to the pill: whether the application fails,
/// or only access to it, with its three readings and any hint.
struct ServiceScope: View {
    var scope: ServiceCardModel.Scope
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !scope.conclusion.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CardMark(mark: scope.mark, size: 8, color: p.listColor(scope.mark))
                    Text(scope.conclusion).foregroundStyle(p.l1).lineLimit(2)
                }
                .font(t.font(11.5))
                Text(scope.detail).font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).padding(.leading, 14)
            }
            ForEach(scope.hints, id: \.self) { hint in
                Label(hint, systemImage: "lightbulb").font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The day's account from the edge in front: where it answered from, its
/// cache statuses and the first byte, as topo's rollups give them.
struct ServiceDay: View {
    var card: ServiceCardModel
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        if !card.answeredFrom.isEmpty || !card.cacheShares.isEmpty || !card.firstByte.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if !card.answeredFrom.isEmpty { row(tr("Answered in 24 h"), card.answeredFrom.joined(separator: ", ")) }
                if !card.cacheShares.isEmpty { row(tr("Cache"), card.cacheShares.joined(separator: ", ")) }
                if !card.firstByte.isEmpty { row(tr("First byte"), card.firstByte) }
            }
            .font(t.font(11))
            .padding(.bottom, 8)
        }
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(p.l3).lineLimit(1).fixedSize()
            Text(value).foregroundStyle(p.l2).lineLimit(2).truncationMode(.tail).help(value)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The edge in front, by its logo, and the colos it answered from: "☁ SJC ·
/// FRA"; its name where it named none.
struct ServiceVia: View {
    var edge: ServiceCardModel.Node
    var colos: [String]
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        HStack(spacing: 4) {
            if let key = ProviderLogo.key(provider: edge.provider, kind: edge.kind) {
                ProviderGlyph(key: key, color: p.l2).frame(width: 11, height: 11)
            }
            Text(colos.isEmpty ? edge.name : colos.joined(separator: " · ")).lineLimit(1)
        }
        .foregroundStyle(p.l2)
        .fixedSize()
    }
}

// MARK: widgets

/// A Service widget's own card: name, three observers with their latency
/// and samples, state and age.
struct WidgetServiceCard: View {
    var card: ServiceCardModel
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                NodeAvatar(provider: card.host.provider, kind: card.host.kind, size: 26, p: p)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.name).font(t.font(12.5, .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(card.isMissing ? card.subtitle : card.onHost).font(t.font(10.5)).foregroundStyle(p.l2)
                        .lineLimit(card.isMissing ? 2 : 1)
                }
            }
            .accessibilityElement(children: .combine)
            ServiceRows(card: card, p: p, t: t, compact: true, vibrant: ctx.widgetRendering != .fullColor)
                .padding(.top, 10).padding(.bottom, 8)
            Spacer(minLength: 0)
            HStack {
                PillView(pill: card.pill, palette: p, type: t)
                Spacer(minLength: 4)
                // A CACHED pill already says the age is of history.
                if let at = card.sampledAt {
                    Age(date: at, now: card.now, live: ctx.liveDates, compact: true)
                        .font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
    }
}

/// A medium Service widget's right side: how it is reached, where it runs,
/// what it depends on, and where the edge in front answered from.
struct WidgetServiceReach: View {
    var card: ServiceCardModel
    var p: CardsPalette
    var t: CardsType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(symbol: nil, title: tr("Reached at"), meta: card.isBlank ? "" : "\(card.endpoints.count)", p: p, t: t)
            if card.isBlank {
                Text(card.isMissing ? "" : tr("Not known now")).font(t.font(12)).foregroundStyle(p.l3)
            } else if let e = card.endpoints.first {
                row(e.mark ?? .unknown, e.host) {
                    if let via = e.via, let key = ProviderLogo.key(provider: via.provider, kind: via.kind) {
                        ProviderGlyph(key: key, color: p.l2).frame(width: 11, height: 11)
                    } else {
                        Text(e.network)
                    }
                }
            } else {
                Text(card.isMissing ? "" : tr("No endpoint declared")).font(t.font(12)).foregroundStyle(p.l3)
            }
            if !card.isBlank { WidgetHeading(symbol: nil, title: tr("Runs on"), meta: "", p: p, t: t).padding(.top, 9) }
            if !card.host.name.isEmpty {
                row(card.hostMark, card.host.name) { Text(Words.kind(card.host.kind)) }
            }
            if let d = card.dependsOn.first {
                row(d.mark, d.name) { Text(tr("needs")) }
            }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Rectangle().fill(p.sep).frame(height: 0.5)
                foot.font(t.font(11)).foregroundStyle(p.l2).padding(.top, 6)
            }
        }
    }

    func row(_ m: Mark, _ name: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 7) {
            CardMark(mark: m, size: 9, color: p.listColor(m))
            Text(name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            trailing().font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1).fixedSize()
        }
        .font(t.font(12))
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Where the edge in front answered from; else every check's mark.
    @ViewBuilder var foot: some View {
        if let edge = card.edge, !card.colos.isEmpty || card.isWithheld {
            HStack(spacing: 5) {
                if let key = ProviderLogo.key(provider: edge.provider, kind: edge.kind) {
                    ProviderGlyph(key: key, color: p.l2).frame(width: 11, height: 11)
                }
                Text(tr("Answered from")).lineLimit(1).fixedSize()
                Spacer(minLength: 2)
                Text(card.isWithheld ? tr("not known") : card.colos.joined(separator: " · "))
                    .fontWeight(.medium).foregroundStyle(card.isWithheld ? p.l3 : p.l1).lineLimit(1)
            }
        } else {
            HStack(spacing: 5) {
                Image(systemName: "target").font(.system(size: 9.5))
                Text(tr("Checks")).lineLimit(1).fixedSize()
                Spacer(minLength: 2)
                if card.checks.isEmpty {
                    Text(card.isBlank ? "—" : tr("none")).foregroundStyle(p.l3)
                } else {
                    HStack(spacing: 2) {
                        ForEach(Array(card.checks.prefix(10).enumerated()), id: \.offset) { _, m in
                            CardMark(mark: m, size: 9, color: p.listColor(m))
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Words.join([tr("Checks"), card.checksText])))
        }
    }
}
