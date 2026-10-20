import Foundation
import TopophanySections

// A service's card in the cells renderer: the server card's box, title and
// pill, and in place of its meters, a line per observer that sees the
// service, as the TUI's service card draws them.

extension CellsBodies {
    /// " ▲ VLESS+Reality Entry (Primary) ": the service's mark before its
    /// name, as the Services tab titles a card.
    func serviceTitle(_ c: ServiceCardModel) -> [Seg] {
        [.t(" ", p.text), .mark(c.mark, p), .t(" ", p.text), .t(c.name + " ", p.text, bold: true)]
    }

    func servicePill(_ c: ServiceCardModel) -> [Seg] {
        [.pill(" " + c.pill.text + " ", fg: c.pill.mark == .unknown || c.pill.mark == .offline ? p.muted : p.tone(c.pill.mark),
               bg: p.pillBackground(c.pill.mark))]
    }

    /// Where it runs, then a line per observer: a mark per check, its
    /// place, the worst check's samples, its median and the day's share up;
    /// then what it depends on and where the edge in front answered from.
    /// `foot` adds that last line.
    func service(_ w: inout CellWriter, _ c: ServiceCardModel, foot: Bool = true) {
        let n = w.frame.columns
        let rows = Array(c.observers.prefix(3))
        focusRow(&w, "service:" + c.id, lines: 1 + max(1, rows.count) + (foot ? 1 : 0))
        if c.isMissing {
            w.line([.t(CellText.truncate(c.subtitle, n), p.muted)])
        } else if !c.isBlank {
            let age = c.shortAge
            var segs: [Seg] = [.t(tr("on") + " ", p.faint)] + Seg.logo(c.host.provider, kind: c.host.kind, p)
            let logo = segs.reduce(0) { $0 + $1.width }
            let room = n - logo - CellText.width(age) - 1
            let name = CellText.truncate(c.host.name, max(4, room))
            segs.append(.t(name, p.kind))
            let app = room - CellText.width(name) - 3
            if !c.application.isEmpty, app >= 4 { segs += [.t(" · ", p.faint), .t(CellText.truncate(c.application, app), p.muted)] }
            w.line(segs, [.t(age, p.faint)])
        }
        if rows.isEmpty, !c.isMissing {
            let (title, why) = c.quiet
            w.line([.glyph(.mark(.offline), p.faint), .t(" " + title.lowercased(with: Locale.current), p.muted)]
                + (why.isEmpty ? [] : [.t(" · " + why, p.faint)]))
        }
        let marks = max(1, min(3, rows.map(\.marks.count).max() ?? 1))
        let place = 9, value = 6, share = 5
        let spark = max(4, n - (marks + 1 + place + 1 + 1 + value + 2 + share))
        for o in rows {
            var segs: [Seg] = o.marks.prefix(marks).map { .mark($0, p) }
            segs.append(.t(String(repeating: " ", count: marks - segs.count + 1), p.text))
            segs += [.t(CellText.pad(CellText.truncate(o.label, place), place), p.text), .t(" ", p.text),
                     .samples(o.history, cells: spark), .t(" ", p.text),
                     .t(CellText.padLeft(o.p50.map(Words.ms) ?? "—", value), o.p50 == nil ? p.faint : p.text),
                     .t("  ", p.text), .t(CellText.padLeft(o.up24h.map(Words.share) ?? "—", share), p.muted)]
            w.line(segs)
        }
        if foot, !c.isBlank { w.line(dependsLine(c, n), viaLine(c)) }
    }

    /// "→ ● PostgreSQL", "used by 3" or "depends on nothing".
    func dependsLine(_ c: ServiceCardModel, _ n: Int) -> [Seg] {
        guard !c.dependsOn.isEmpty else {
            return [.t(c.usedBy > 0 ? tr("used by \(c.usedBy)") : tr("depends on nothing"), p.faint)]
        }
        var segs: [Seg] = [.t("→ ", p.accent)]
        for (i, d) in c.dependsOn.prefix(2).enumerated() {
            if i > 0 { segs.append(.t("  ", p.text)) }
            segs += [.mark(d.mark, p), .t(" " + CellText.truncate(d.name, 14), p.text)]
        }
        return segs
    }

    /// "⇠ [logo] SJC · FRA": the edge in front and where it answered from;
    /// without one, how many checks there are.
    func viaLine(_ c: ServiceCardModel) -> [Seg] {
        if let e = c.edge {
            return [.t("⇠ ", p.muted)] + Seg.logo(e.provider, kind: e.kind, p)
                + [.t(c.colos.isEmpty ? e.name : c.colos.joined(separator: " · "), p.muted)]
        }
        return c.checks.isEmpty ? [] : [.t(tr("\(c.checks.count) checks"), p.faint)]
    }

    /// "public   https://www.example.invalid/   ●": the address it is
    /// known by, and its mark where a check targets it.
    func knownAt(_ c: ServiceCardModel, _ n: Int) -> ([Seg], [Seg]) {
        guard let e = c.knownAt else { return ([.t(c.isBlank ? "" : tr("no endpoint declared"), p.faint)], []) }
        let mark: Seg = e.mark.map { .mark($0, p) } ?? .t("·", p.faint)
        return ([.t(CellText.pad(e.network, 9), e.network == "public" ? p.accent2 : p.muted),
                 .t(CellText.truncate(e.address, n - 12), p.text)], [mark])
    }
}

extension CellsWidget.Layout {
    // MARK: Service

    var serviceCard: ServiceCardModel {
        if let c = model.service { return c }
        let id = if case .service(let s) = model.kind { s } else { "" }
        return ServiceCardModel(id: id, name: id.isEmpty ? tr("no service chosen") : id, application: "",
                                host: .init(name: "", kind: "", provider: ""), hostMark: .offline, mark: .offline,
                                pill: .cached, isWithheld: true, isMissing: true, observers: [], checks: [],
                                placeholder: id.isEmpty ? tr("choose one in Edit Widget") : tr("not received yet"),
                                sampledAt: nil, now: status.now)
    }

    /// Small: its name and age, then each observer on two lines, its
    /// latency over its samples, and where it runs where there is room.
    /// Medium: the panel's card, and the address it is known by.
    mutating func service(_ size: WidgetSize) {
        let c = serviceCard
        let x0 = CellsWidget.pad.side, x1 = CellsWidget.pad.side + Double(cols) * cell
        let b = self.b
        let p = self.p
        guard size == .small else {
            head(cols)
            w.box(b.serviceTitle(c), b.servicePill(c), x0: x0, x1: x1, style: style) { w in
                b.service(&w, c)
                if !c.isBlank {
                    let (left, right) = b.knownAt(c, w.frame.columns)
                    w.line(left, right)
                }
            }
            return
        }
        let age = c.isBlank ? "" : c.isWithheld ? tr("last") : c.sampledAt.map { Words.span(since: $0, now: c.now, style: .compact) } ?? ""
        w.line([.mark(c.mark, p), .t(" " + CellText.truncate(c.name, cols - 3 - CellText.width(age)), p.text, bold: true)],
               [.t(age, p.faint)])
        let rows = Array(c.observers.prefix(3))
        let title: [Seg] = rows.isEmpty ? [.t(" " + tr("SERVICE") + " ", p.accent, bold: true)]
            : [.t(" " + tr("SEEN FROM"), p.accent, bold: true), .t(" \(rows.count) ", p.muted)]
        let room = linesLeft
        w.box(title, b.servicePill(c), x0: x0, x1: x1, style: style) { w in
            let n = w.frame.columns
            var used = 0
            for o in rows where used + 2 <= room {
                let marks: [Seg] = o.marks.prefix(2).map { .mark($0, p) }
                let value = o.p50.map(Words.ms) ?? "—"
                w.line(marks + [.t(" " + CellText.truncate(o.label, n - 8 - marks.count), p.text)],
                       [.t(value, o.p50 == nil ? p.faint : p.text)])
                w.line([.t("  ", p.text), .samples(o.history, cells: n - 2)])
                used += 2
            }
            if rows.isEmpty {
                if c.isMissing {
                    for line in CellText.wrap(c.subtitle, n, lines: 2) { w.line([.t(line, p.muted)]) }
                } else {
                    let (title, why) = c.quiet
                    w.line([.glyph(.mark(.offline), p.faint), .t(" " + title.lowercased(with: Locale.current), p.muted)])
                    if !why.isEmpty {
                        w.line([.t(CellText.truncate(CellText.width(why) + 2 <= n ? "  " + why : why, n), p.faint)])
                    }
                }
                used = 2
            }
            // Where it runs, at the foot of the box, when the observers
            // leave room for it.
            if !c.isBlank, !c.host.name.isEmpty, room - used >= 1 {
                w.blank(Double(room - used - 1) * w.lineHeight)
                let logo = Seg.logo(c.host.provider, kind: c.host.kind, p)
                let used = 3 + logo.reduce(0) { $0 + $1.width }
                w.line([.t(tr("on") + " ", p.faint)] + logo + [.t(CellText.truncate(c.host.name, n - used), p.kind)])
            }
        }
    }
}
