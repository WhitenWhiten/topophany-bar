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
                let lead = short ? tr(" last: ") : tr(" last snapshot said ")
                w.line([.mark(.offline, p), .t(lead, p.muted),
                        .t(CellText.truncate(said, n - 1 - CellText.width(lead)), p.text, bold: true)])
            } else {
                w.line([.mark(.offline, p), .t(" " + CellText.truncate(tr("nothing current is known"), n - 2), p.muted)])
            }
        }
        if !short {
            let inc = s.incidents ?? 0
            let left: [Seg] = s.isBlind
                ? [.glyph(.flag, p.faint), .t(" ", p.text), .t(tr("incidents not known"), p.faint)]
                : [.glyph(.flag, inc > 0 ? p.down : p.faint), .t(" ", p.text), .t("\(inc)", inc > 0 ? p.text : p.faint, bold: inc > 0),
                   .t(inc == 1 ? tr(" incident") : tr(" incidents"), p.muted)]
            var right: [Seg] = []
            if let live = s.observersLive, let all = s.observersAll, !s.isBlind {
                right = [.glyph(.target, p.accent2), .t(" ", p.text), .t("\(live)/\(all)", p.text, bold: true),
                         .t(all == 1 ? tr(" observer live") : tr(" observers live"), p.muted)]
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
        // Problems left out for room are counted as problems, never as calm.
        if problems.count > max {
            let rest = problems[max...]
            w.line([.mark(rest.first?.mark ?? .unknown, p), .t(" " + tr("+\(rest.count) more see a problem"), p.muted)])
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

    /// `clock` adds the time where the server is: the panel's, which is
    /// drawn every second, never a widget's.
    func server(_ w: inout CellWriter, _ c: ServerCardModel, bar: Int = 20, labelWidth: Int = 7, detail: Bool = true,
                observes: Bool = false, short: Bool = false, clock: Bool = false) {
        focusRow(&w, "server:" + c.id, lines: 4)
        let age = c.sampledAt.map { Words.ago($0, now: c.now, style: .compact) } ?? ""
        let ageText = c.isWithheld ? tr("last \(age)") : age
        if c.isMissing {
            w.line([.t(c.place, p.muted)])
        } else {
            // What fits beside the age: the provider goes first, then the
            // place shortens; the kind and the time stay.
            let time = clock ? c.localTime : nil
            let room = w.frame.columns - CellText.width(ageText) - 1
            func line(_ provider: String, _ place: String) -> [Seg] {
                var segs: [Seg] = []
                for (i, part) in [c.kind, provider, place].enumerated() where !part.isEmpty {
                    if !segs.isEmpty { segs.append(.t(" · ", p.faint)) }
                    segs.append(.t(part, i == 0 ? p.kind : p.muted))
                }
                if let time { segs += [.t(" · ", p.faint), .t(time, p.text)] }
                return segs
            }
            func width(_ segs: [Seg]) -> Int { segs.reduce(0) { $0 + $1.width } }
            var segs = line(c.provider, c.place)
            if width(segs) > room { segs = line("", c.place) }
            if width(segs) > room {
                let over = width(segs) - room
                segs = line("", CellText.truncate(c.place, max(1, CellText.width(c.place) - over)))
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

    // MARK: time zones

    /// Two lines a zone: its time, places, marks and offset, then its zone
    /// name and its day ribbon, every ribbon as wide as the others so the
    /// now ticks line up.
    func zones(_ w: inout CellWriter, _ z: ZonesSection) {
        let n = w.frame.columns
        // As wide as the widest clock or zone name: "GMT-10", "GMT+5:30".
        let tw = z.zones.map { max(CellText.width($0.clock), min(CellText.width($0.zoneName), 9)) }.max() ?? 0
        let rw = z.zones.map { max(CellText.width($0.relative), CellText.width($0.day)) }.max() ?? 0
        let ribbon = max(8, n - tw - 2 - 1 - rw)
        // Night is the darker of the palette's quiet tones, day the lighter.
        let dark = p.ink.r + p.ink.g + p.ink.b < 1.5
        let (night, day) = dark ? (p.track, p.muted) : (p.faint, p.track)
        for zone in z.zones {
            var marks: [Seg] = zone.servers.prefix(8).map { .mark($0.mark, p) }
            if zone.servers.count > 8 { marks.append(.t("+\(zone.servers.count - 8)", p.faint)) }
            let room = n - tw - 2 - marks.reduce(0) { $0 + $1.width } - 1 - rw - 1
            w.line([.t(CellText.pad(zone.clock, tw), p.text, bold: true), .t("  ", p.text),
                    .t(CellText.truncate(zone.title, max(1, room)), p.text)],
                   marks + [.t(" ", p.text), .t(CellText.padLeft(zone.relative, rw), zone.isHere ? p.accent : p.muted)])
            let cells = (0..<ribbon).map { i in
                night.mix(day, ZonesSection.daylight(ZonesSection.hour(zone, at: (Double(i) + 0.5) / Double(ribbon))))
            }
            w.line([.t(CellText.pad(CellText.truncate(zone.zoneName, tw), tw), p.faint), .t("  ", p.text),
                    .ribbon(cells, midnights: ZonesSection.midnights(zone), now: p.accent)],
                   [.t(CellText.padLeft(zone.day, rw), p.faint)])
        }
        if z.unplaced > 0 { w.line([.t(tr("\(z.unplaced) without a time zone"), p.faint)]) }
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
    @Environment(\.panelActions) private var actions
    @State private var hover: String?

    static let columns = 48
    nonisolated static let radius = 12.0

    var body: some View {
        let scene = Self.scene(model, ctx: ctx, focusFirstAttention: focusFirstAttention, hover: hover)
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        fitted(scene)
            .background(shape.fill(Color(CellsPalette(ctx.theme).ink)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(CellsPalette(ctx.theme).line.opacity(ctx.increaseContrast ? 1 : 0.85)), lineWidth: 1))
            .overlay(shape.stroke(Color.black.opacity(0.7), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CellsAccessibility.panel(model))
            .overlay(alignment: .bottomLeading) { keys(scene) }
    }

    /// The footer's keycaps are buttons too, and `,` and `q` work alone, as
    /// the footer shows them. The footer is always at the bottom.
    func keys(_ scene: CellScene) -> some View {
        ZStack(alignment: .bottomLeading) {
            key(scene, "open", tr("Open in Terminal"), nil) { actions.openTerminal() }
            key(scene, "settings", tr("Settings"), KeyboardShortcut(",", modifiers: [])) { actions.openSettings() }
            key(scene, "quit", tr("Quit"), KeyboardShortcut("q", modifiers: [])) { actions.quit() }
        }
    }

    @ViewBuilder
    func key(_ scene: CellScene, _ id: String, _ label: String, _ shortcut: KeyboardShortcut?,
             action: @escaping @MainActor () -> Void) -> some View {
        if let r = scene.regions[id] {
            Button(action: action) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(width: r.width, height: r.height)
                .onHover { inside in
                    if inside { hover = id } else if hover == id { hover = nil }
                }
                .keyboardShortcut(shortcut)
                .accessibilityLabel(label)
                .offset(x: r.minX, y: r.maxY - scene.size.height)
        }
    }

    /// The whole scene, or, when it is taller than the screen allows, the
    /// header, Status (when pinned) and footer fixed and the rest scrolling.
    @ViewBuilder func fitted(_ scene: CellScene) -> some View {
        let h = scene.size.height
        if let maxH = ctx.maxHeight, h > maxH,
           let header = scene.marks["header"], let status = scene.marks["status"], let footer = scene.marks["footer"] {
            let top = model.pinStatus ? status : header
            VStack(spacing: 0) {
                slice(scene, top: 0, bottom: top)
                ScrollView(.vertical) { slice(scene, top: top, bottom: footer) }
                    .scrollIndicators(.automatic)
                    .frame(height: max(80, maxH - top - (h - footer)))
                slice(scene, top: footer, bottom: h)
            }
            .frame(width: scene.size.width)
        } else {
            CellCanvas(scene: scene)
        }
    }

    /// A band of the scene, from `top` to `bottom`.
    func slice(_ scene: CellScene, top: Double, bottom: Double) -> some View {
        CellCanvas(scene: scene)
            .offset(y: -top)
            .frame(width: scene.size.width, height: bottom - top, alignment: .top)
            .clipped()
    }

    static func scene(_ model: PanelModel, ctx: RenderContext, focusFirstAttention: Bool = false, hover: String? = nil) -> CellScene {
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

        var marks = ["header": w.y]
        let x0 = 6.0, x1 = width - 6
        func title(_ t: String, _ extra: String? = nil) -> [Seg] {
            var s: [Seg] = [.t(" " + t, p.accent, bold: true)]
            if let extra { s += [.t(" · ", p.faint), .t(extra, p.muted)] }
            return s + [.t(" ", p.text)]
        }
        let st = model.status
        let updated = (st.isBlind ? st.lastKnown?.at : st.updatedAt).map { Words.ago($0, now: st.now, style: .compact) } ?? ""
        // With nothing ever received there is no age, and "cached" stands
        // alone: Japanese and Chinese put the age before it.
        let age = st.isBlind ? (updated.isEmpty ? tr("cached") : tr("cached \(updated)")) : tr("updated \(updated)")
        w.box(title(tr("STATUS")), [.t(" " + age + " ", p.muted)],
              x0: x0, x1: x1, style: .panel, tint: b.statusTint(st)) { w in
            b.status(&w, st, blockHeight: 54)
        }
        marks["status"] = w.y + 2
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
                    w.box(b.serverTitle(c), b.serverPill(c), x0: x0, x1: x1, style: .panel) { b.server(&$0, c, clock: true) }
                }
            case .zones(let z):
                w.box(title(tr("TIME ZONES"), "\(z.zones.count)"), [.t(" " + tr("\(z.serverCount) servers") + " ", p.muted)],
                      x0: x0, x1: x1, style: .panel) { b.zones(&$0, z) }
            case .mac(.server(let c, _)):
                w.box(b.serverTitle(c, prefix: title(tr("THIS MAC")).dropLast()), b.serverPill(c), x0: x0, x1: x1, style: .panel) {
                    b.server(&$0, c, observes: true, clock: true)
                }
            case .mac(.local(let l)):
                w.box(title(tr("THIS MAC"), tr("local readings")), [.t(" " + l.model + " ", p.muted)], x0: x0, x1: x1, style: .panel) {
                    b.local(&$0, l)
                }
            }
        }

        // Footer: keycaps and the connection. Live, the project is cut to
        // fit, as the header shows it whole; otherwise the connection says
        // what's wrong, and takes a line of its own above the keycaps when
        // it doesn't fit beside them.
        w.y += 9
        let footTop = w.y
        marks["footer"] = footTop
        func key(_ k: String, _ label: String, _ id: String) -> (id: String, segs: [Seg]) {
            (id, [.key(" \(k) "), .t(" " + label + "  ", hover == id ? p.text : p.muted)])
        }
        let keys = [key("↵", tr("Open"), "open"), key(",", tr("Settings"), "settings"), key("q", tr("Quit"), "quit")]
        let room = columns - keys.reduce(0) { $0 + $1.segs.reduce(0) { $0 + $1.width } }
        let conn: Seg
        var ownLine = false
        if ch.isLive {
            let text = Words.join([ch.project, ch.updatedAt.map { Words.span(since: $0, now: ch.now, style: .compact) } ?? ""])
            conn = .t(CellText.truncate(text, room), p.faint)
        } else {
            let text = ch.connection == .unreachable ? tr("unreachable") : ch.connectionText.lowercased()
            ownLine = CellText.width(text) > room
            conn = .t(CellText.truncate(text, ownLine ? columns : room), p.down)
        }
        let footHeight = ownLine ? 48.0 : 28
        w.items.append(.fill(CGRect(x: 0, y: footTop, width: width, height: footHeight), p.inkHigh, radius: 0))
        w.items.append(.fill(CGRect(x: 0, y: footTop, width: width, height: 1), p.line.opacity(0.7), radius: 0))
        w.y = footTop + 5
        if ownLine {
            w.line([conn])
            w.y += 2
        }
        // Each keycap and its label is a button.
        var regions: [String: CGRect] = [:]
        var col = 0
        for k in keys {
            let n = k.segs.reduce(0) { $0 + $1.width }
            regions[k.id] = CGRect(x: w.frame.x + Double(col) * w.cell - 2, y: w.y - 4, width: Double(n - 2) * w.cell + 4, height: w.lineHeight + 8)
            col += n
        }
        w.line(keys.flatMap(\.segs), ownLine ? [] : [conn])
        w.y = footTop + footHeight
        var scene = CellScene(size: CGSize(width: width, height: w.y), metrics: m, items: w.items)
        scene.marks = marks
        scene.regions = regions
        return scene
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
