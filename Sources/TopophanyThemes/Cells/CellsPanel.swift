import LocalReadings
import SwiftUI
import TopophanySections

/// The Terminal look's section bodies: the TUI's panels, line by line.
/// Shared by the panel and the widgets, which call them at other widths.
struct CellsBodies {
    var p: CellsPalette
    var focus: String?

    // MARK: status

    func statusTint(_ s: StatusSection) -> RGBA { p.tone(s.mark).mix(p.ink, 0.42) }

    /// The verdict, the big count, every check by health and the observers.
    func status(_ w: inout CellWriter, _ s: StatusSection, short: Bool = false, blockHeight: Double) {
        let tone = p.tone(s.mark)
        let title = short ? s.tuiShortTitle : s.tuiTitle
        w.line([.mark(s.mark, p), .t(" " + CellText.truncate(title, w.frame.columns - 2), tone, bold: true)])
        // The big number and the two lines beside it.
        let big = s.big
        let bigW = CellWriter.bigWidth(big.digits)
        let top = w.y
        w.bigDigits(big.digits, color: tone, x: w.frame.x + w.cell, y: top, height: blockHeight)
        let textX = w.frame.x + Double(1 + bigW + 2) * w.cell
        let cols = w.frame.columns - (1 + bigW + 2)
        let lines: (String, String)
        if short {
            let words = big.top.split(separator: " ", maxSplits: 1).map(String.init)
            lines = (words.first ?? "", words.count > 1 ? words[1] : "")
        } else {
            lines = (big.top, big.bottom)
        }
        w.draw([.t(CellText.truncate(lines.0, cols), p.text)], x: textX, y: top + 2)
        w.draw([.t(CellText.truncate(lines.1, cols), p.muted)], x: textX, y: top + 2 + w.lineHeight)
        w.y = top + blockHeight
        let n = w.frame.columns
        if let c = s.counts?.complete, !s.isBlind {
            let total = Double(max(1, c.up + c.warning + c.down + c.unknown))
            func share(_ v: Int) -> Int { Int((Double(v) / total * Double(n)).rounded()) }
            var parts = [(share(c.up), p.up), (share(c.warning), p.warn), (share(c.down), p.down), (share(c.unknown), p.unknown)]
            parts[0].0 = max(0, parts[0].0 + n - parts.reduce(0) { $0 + $1.0 })
            w.line([.rule(parts)])
            func count(_ v: Int, _ m: Mark, _ word: String?) -> [Seg] {
                let on = v > 0
                return [.glyph(.mark(m), on ? p.tone(m) : p.faint), .t(" "  , p.text), .t("\(v)", on ? p.text : p.faint, bold: on),
                        .t(word.map { " \($0)  " } ?? " ", on ? p.muted : p.faint)]
            }
            if short {
                w.line(count(c.up, .up, nil) + count(c.warning, .degraded, nil) + count(c.down, .down, nil) + count(c.unknown, .unknown, nil))
            } else {
                w.line(count(c.up, .up, tr("up")) + count(c.warning, .degraded, tr("warn")) + count(c.down, .down, tr("down"))
                       + count(c.unknown, .unknown, tr("unknown")))
            }
        } else {
            w.line([.dashes(n, p.faint)])
            if let k = s.lastKnown {
                let said = StatusSection.words(for: k)
                w.line([.mark(.offline, p), .t(short ? tr(" last: ") : tr(" last snapshot said "), p.muted),
                        .t(CellText.truncate(said, n - 21), p.text, bold: true)])
            } else {
                w.line([.mark(.offline, p), .t(" " + CellText.truncate(tr("nothing current is known"), n - 2), p.muted)])
            }
        }
        if !short {
            let inc = s.incidents ?? 0
            let left: [Seg] = s.isBlind
                ? [.glyph(.flag, p.faint), .t(" ", p.text), .t(tr("incidents not known"), p.faint)]
                : [.glyph(.flag, inc > 0 ? p.down : p.faint), .t(" ", p.text), .t("\(inc)", inc > 0 ? p.text : p.faint, bold: inc > 0),
                   .t(tr(" incidents"), p.muted)]
            var right: [Seg] = []
            if let live = s.observersLive, let all = s.observersAll, !s.isBlind {
                right = [.glyph(.target, p.accent2), .t(" ", p.text), .t("\(live)/\(all)", p.text, bold: true), .t(tr(" observers live"), p.muted)]
            }
            w.line(left, right)
        }
    }

    // MARK: seen from

    func seen(_ w: inout CellWriter, _ s: SeenFromSection, max: Int = 99) {
        let n = w.frame.columns
        guard let problems = s.problems else {
            w.line([.mark(.offline, p), .t(" " + tr("not known while offline"), p.muted)])
            return
        }
        if problems.isEmpty {
            w.line([.mark(.up, p), .t(" " + CellText.truncate(tr("all \(s.calm) observers report no problem"), n - 2), p.muted)])
            return
        }
        for o in problems.prefix(max) {
            focusRow(&w, "seen:" + o.id, lines: 1)
            w.line([.mark(o.mark, p), .t(" " + CellText.truncate(o.name, n - 10), p.text)], [.t(o.note, p.tone(o.mark))])
        }
        if s.calm > 0 {
            w.line([.mark(.up, p), .t(" " + tr("\(s.calm) others report no problem"), p.muted)])
        }
    }

    // MARK: needs attention

    func attention(_ w: inout CellWriter, _ a: AttentionSection, limit: Int, compact: Bool = false, forceFocusFirst: Bool = false) {
        let n = w.frame.columns
        for (i, item) in a.items.prefix(limit).enumerated() {
            let st = item.pill.text
            let lines = compact ? 1 : 2
            if forceFocusFirst && i == 0 { highlight(&w, lines: lines) } else { focusRow(&w, "attention:" + item.id, lines: lines) }
            w.line([.mark(item.mark, p), .t(" " + CellText.truncate(item.title, n - 3 - CellText.width(st) - 1), p.text, bold: true)],
                   [.t(st, p.tone(item.mark), bold: true)])
            if !compact {
                let sub = Words.join([Words.kind(item.kind), item.observerName,
                                      item.since.map { Words.span(since: $0, now: a.now, style: .compact) } ?? ""])
                w.line([.t("  " + CellText.truncate(sub, n - 2), p.muted)])
            }
        }
        let rest = a.total - min(limit, a.items.count)
        if rest > 0 {
            focusRow(&w, "attention:more", lines: 1)
            w.line([.t(tr("+\(rest) more"), p.faint)], compact ? [] : [.glyph(.enter, p.accent), .t(" " + tr("open in topo"), p.faint)])
        }
    }

    // MARK: services

    func applications(_ w: inout CellWriter, _ a: ApplicationsSection, nameWidth: Int = 15, tight: Bool = false, notes: Bool = true) {
        for row in a.rows {
            focusRow(&w, "app:" + row.id, lines: 1)
            var segs: [Seg] = [.mark(row.mark, p), .t(" ", p.text),
                               .t(CellText.pad(row.name, nameWidth), p.text, bold: row.mark == .degraded || row.mark == .down),
                               .t(" ", p.text)]
            let room = w.frame.columns - 2 - nameWidth - 1 - (notes ? CellText.width(row.note) + 1 : 0)
            let per = tight ? 1 : 2
            for m in row.services.prefix(max(0, room / per)) {
                segs.append(.mark(m, p))
                if !tight { segs.append(.t(" ", p.text)) }
            }
            let showNote = notes && !row.note.isEmpty && row.note != tr("all up")
            let noteColor = row.noteNeedsLook ? p.warn : p.muted
            w.line(segs, showNote ? [.t(row.note, noteColor)] : [])
        }
    }

    // MARK: servers

    func serverTitle(_ c: ServerCardModel, prefix: [Seg] = []) -> [Seg] {
        prefix + [.t(" ", p.text), .mark(c.mark, p), .t(" " + c.name + " ", p.text, bold: true)]
    }

    func serverPill(_ c: ServerCardModel) -> [Seg] {
        [.pill(" " + c.pill.text + " ", fg: c.pill.mark == .unknown || c.pill.mark == .offline ? p.muted : p.tone(c.pill.mark),
               bg: p.pillBackground(c.pill.mark))]
    }

    func server(_ w: inout CellWriter, _ c: ServerCardModel, bar: Int = 20, labelWidth: Int = 7, detail: Bool = true,
                observes: Bool = false, short: Bool = false) {
        focusRow(&w, "server:" + c.id, lines: 4)
        let age = c.sampledAt.map { Words.ago($0, now: c.now, style: .compact) } ?? ""
        let ageText = c.isWithheld ? tr("last \(age)") : age
        if c.isMissing {
            w.line([.t(c.place, p.muted)])
        } else {
            var segs: [Seg] = []
            for (i, part) in [c.kind, c.provider, c.place].filter({ !$0.isEmpty }).enumerated() {
                if !segs.isEmpty { segs.append(.t(" · ", p.faint)) }
                segs.append(.t(part, i == 0 && part == c.kind ? p.kind : p.muted))
            }
            w.line(segs, [.t(ageText, p.faint)])
        }
        func shown(_ m: ServerCardModel.Meter) -> String { m.detail.replacingOccurrences(of: " / ", with: "/") }
        // The bar gives way to a detail column of at least "76.7/128 GiB",
        // so bars line up from card to card and a space precedes the detail.
        let widest = detail ? max(12, [c.cpu, c.memory, c.disk].map { CellText.width(shown($0)) }.max() ?? 0) : 0
        let bar = widest > 0 ? min(bar, w.frame.columns - labelWidth - 7 - 1 - widest) : bar
        func row(_ label: String, _ m: ServerCardModel.Meter) {
            let value = m.percent.map { CellText.padLeft(Words.percent($0), 6) } ?? "     —"
            let color = m.percent.map { p.load($0, limit: m.limit) } ?? p.track
            w.line([.t(CellText.pad(label, labelWidth), p.muted), .t(value, m.percent == nil ? p.faint : p.text, bold: m.percent != nil),
                    .t(" ", p.text), .bar(cells: bar, percent: m.percent, limit: m.limit, color: color, withheld: m.percent == nil)],
                   detail && !m.detail.isEmpty ? [.t(shown(m), p.muted)] : [])
        }
        row(tr("CPU"), c.cpu)
        row(labelWidth < 7 ? tr("MEM") : tr("MEMORY"), c.memory)
        row(tr("DISK"), c.disk)
        if observes, let o = c.observes.first {
            w.line([.glyph(.target, p.accent2), .t(tr(" from here  "), p.muted), .mark(o.mark, p),
                    .t(" " + o.text, o.mark == .up ? p.text : p.tone(o.mark))], [.t(ageText, p.faint)])
        }
    }

    // MARK: this Mac

    func local(_ w: inout CellWriter, _ l: LocalSection) {
        let n = 19
        func label(_ s: String) -> Seg { .t(CellText.pad(s, 7), p.muted) }
        if let c = l.cpu {
            let h = Array(l.cpuHistory.suffix(n))
            w.line([label(tr("CPU")), .t(CellText.padLeft(Words.percent(c.total), 6), p.text, bold: true), .t(" ", p.text),
                    .sparks(h, top: h.max() ?? 1, p.accent)],
                   [.t(tr("sys \(Int(c.system.rounded())) usr \(Int(c.user.rounded()))"), p.muted)])
        }
        if let m = l.memory {
            w.line([label(tr("MEMORY")), .t(CellText.padLeft(Words.percent(m.usedPercent), 6), p.text, bold: true), .t(" ", p.text),
                    .bar(cells: n, percent: m.usedPercent, limit: nil, color: p.accent, withheld: false)],
                   m.pressurePercent.map { [.t(tr("press \(Words.percent($0, digits: 0))"), p.muted)] } ?? [])
        }
        if let s = l.storage {
            w.line([label(tr("DISK")), .t(CellText.padLeft(Words.percent(s.usedPercent), 6), p.text, bold: true), .t(" ", p.text),
                    .bar(cells: n, percent: s.usedPercent, limit: nil, color: p.accent, withheld: false)],
                   [.t("\(Int((Double(s.usedBytes) / 1e9).rounded()))/\(Int((Double(s.totalBytes) / 1e9).rounded())) GB", p.muted)])
        }
        if let net = l.network {
            w.line([label(tr("NET")), .t("↓ ", p.accent), .t(Words.rate(net.receivedPerSecond), p.text, bold: true),
                    .t("  ↑ ", p.accent2), .t(Words.rate(net.sentPerSecond), p.text, bold: true)],
                   [.t(net.displayName, p.muted)])
        }
        if let b = l.battery {
            let rest = l.batteryRemaining
            w.line([label(tr("POWER")), .t("\(b.percent)%", p.text, bold: true), .t(" " + l.batteryState.lowercased(), b.state == .discharging ? p.muted : p.up),
                    .t(rest.isEmpty ? "" : " · " + rest, p.muted)])
        }
    }

    // MARK: focus

    func focusRow(_ w: inout CellWriter, _ id: String, lines: Int) {
        guard focus == id else { return }
        highlight(&w, lines: lines)
    }

    func highlight(_ w: inout CellWriter, lines: Int) {
        w.focus(x0: w.frame.x - w.cell, x1: w.frame.x + Double(w.frame.columns + 1) * w.cell,
                top: w.y, height: Double(lines) * w.lineHeight)
    }
}

/// The Terminal panel: 48 columns of SF Mono 12 inside 7 pt margins.
struct CellsPanel: View {
    var model: PanelModel
    var ctx: RenderContext
    var focusFirstAttention = false

    static let columns = 48

    var body: some View {
        let scene = Self.scene(model, ctx: ctx, focusFirstAttention: focusFirstAttention)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        CellCanvas(scene: scene)
            .background(shape.fill(Color(CellsPalette(ctx.theme).ink)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(CellsPalette(ctx.theme).line.opacity(ctx.increaseContrast ? 1 : 0.85)), lineWidth: 1))
            .overlay(shape.stroke(Color.black.opacity(0.7), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CellsAccessibility.panel(model))
    }

    static func scene(_ model: PanelModel, ctx: RenderContext, focusFirstAttention: Bool = false) -> CellScene {
        let m = CellMetrics.panel
        let p = CellsPalette(ctx.theme)
        let width = Double(columns) * m.cell + 14
        var w = CellWriter(metrics: m, palette: p, width: width, frame: .init(x: 7, columns: columns))
        let b = CellsBodies(p: p, focus: ctx.focus)
        let ch = model.chrome

        // Header: the TUI's top bar.
        w.items.append(.fill(CGRect(x: 0, y: 0, width: width, height: 28), p.inkHigh, radius: 0))
        w.items.append(.fill(CGRect(x: 0, y: 27, width: width, height: 1), p.line.opacity(0.7), radius: 0))
        w.y = 5
        let live: [Seg] = ch.isLive ? [.mark(.up, p), .t(" " + tr("LIVE"), p.up, bold: true)]
            : [.mark(.offline, p), .t(" " + tr("OFFLINE"), p.down, bold: true)]
        let head = CellText.truncate(ch.view, columns - 26 - CellText.width(ch.project))
        w.line([.glyph(.logo, p.accent), .t(" TOPOPHANY", p.accent, bold: true), .t(" ╱ ", p.faint), .t(ch.project, p.text, bold: true),
                .t(" · " + head, p.faint)], live)
        w.y = 28

        let x0 = 6.0, x1 = width - 6
        func title(_ t: String, _ extra: String? = nil) -> [Seg] {
            var s: [Seg] = [.t(" " + t, p.accent, bold: true)]
            if let extra { s += [.t(" · ", p.faint), .t(extra, p.muted)] }
            return s + [.t(" ", p.text)]
        }
        let st = model.status
        let updated = (st.isBlind ? st.lastKnown?.at : st.updatedAt).map { Words.ago($0, now: st.now, style: .compact) } ?? ""
        w.box(title(tr("STATUS")), [.t(" " + (st.isBlind ? tr("cached \(updated)") : tr("updated \(updated)")) + " ", p.muted)],
              x0: x0, x1: x1, style: .panel, tint: b.statusTint(st)) { w in
            b.status(&w, st, blockHeight: 54)
        }
        for s in model.sections {
            switch s {
            case .seen(let seen):
                w.box(title(tr("SEEN FROM"), seen.total.map { "\($0)" }), x0: x0, x1: x1, style: .panel) { b.seen(&$0, seen) }
            case .attention(let a):
                w.box(title(tr("NEEDS ATTENTION"), "\(a.total)"), x0: x0, x1: x1, style: .panel) {
                    b.attention(&$0, a, limit: a.items.count, forceFocusFirst: focusFirstAttention)
                }
            case .applications(let a):
                w.box(title(tr("SERVICES"), tr("\(a.serviceCount) in \(a.rows.count) apps")), x0: x0, x1: x1, style: .panel) {
                    b.applications(&$0, a)
                }
            case .servers(let cards):
                for c in cards {
                    w.box(b.serverTitle(c), b.serverPill(c), x0: x0, x1: x1, style: .panel) { b.server(&$0, c) }
                }
            case .mac(.server(let c, _)):
                w.box(b.serverTitle(c, prefix: title(tr("THIS MAC")).dropLast()), b.serverPill(c), x0: x0, x1: x1, style: .panel) {
                    b.server(&$0, c, observes: true)
                }
            case .mac(.local(let l)):
                w.box(title(tr("THIS MAC"), tr("local readings")), [.t(" " + l.model + " ", p.muted)], x0: x0, x1: x1, style: .panel) {
                    b.local(&$0, l)
                }
            }
        }

        // Footer: keycaps and the connection.
        w.y += 9
        let footTop = w.y
        w.items.append(.fill(CGRect(x: 0, y: footTop, width: width, height: 28), p.inkHigh, radius: 0))
        w.items.append(.fill(CGRect(x: 0, y: footTop, width: width, height: 1), p.line.opacity(0.7), radius: 0))
        w.y = footTop + 5
        func key(_ k: String, _ label: String) -> [Seg] { [.key(" \(k) "), .t(" " + label + "  ", p.muted)] }
        let keys = key("↵", tr("Open")) + key(",", tr("Settings")) + key("q", tr("Quit"))
        let room = columns - keys.reduce(0) { $0 + $1.width }
        let conn: [Seg] = ch.isLive
            ? [.t(CellText.truncate(Words.join([ch.project, ch.updatedAt.map { Words.span(since: $0, now: ch.now, style: .compact) } ?? ""]), room), p.faint)]
            : [.t(CellText.truncate(ch.connection == .unreachable ? tr("unreachable") : ch.connectionText.lowercased(), room), p.down)]
        w.line(keys, conn)
        w.y = footTop + 28
        return CellScene(size: CGSize(width: width, height: w.y), metrics: m, items: w.items)
    }
}

/// What VoiceOver reads for a cell scene: the same words, as sentences.
enum CellsAccessibility {
    static func panel(_ m: PanelModel) -> String {
        var parts = [m.status.title, m.status.subtitle]
        if let s = m.seen, let problems = s.problems {
            parts.append(problems.isEmpty ? tr("All \(s.calm) observers report no problem")
                                          : problems.map { "\($0.name) \($0.note)" }.joined(separator: ", "))
        }
        if let a = m.attention {
            parts.append(tr("\(a.total) need attention"))
            parts += a.items.map { "\($0.title), \($0.pill.text)" }
        }
        return parts.joined(separator: ". ")
    }
}
