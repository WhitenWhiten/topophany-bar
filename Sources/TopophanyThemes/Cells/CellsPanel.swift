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
        if let sources = s.sources {
            self.sources(&w, sources, tone: tone, short: short, blockHeight: blockHeight)
            if let notice = s.notice { for line in CellText.wrap(notice, w.frame.columns, lines: 2) { w.line([.t(line, p.muted)]) } }
            return
        }
        big(&w, s.big, tone: tone, short: short, blockHeight: blockHeight)
        let n = w.frame.columns
        if let c = s.counts?.complete, !s.isBlind {
            let total = Double(max(1, c.up + c.warning + c.down + c.unknown))
            func share(_ v: Int) -> Int { Int((Double(v) / total * Double(n)).rounded()) }
            // In one tone a run has no shape to tell up from trouble, so
            // weight does, as on the cards bar: trouble in the full ink.
            var parts = w.plain
                ? [(share(c.up), p.text.opacity(0.3)), (share(c.warning), p.text), (share(c.down), p.text),
                   (share(c.unknown), p.text.opacity(0.55))]
                : [(share(c.up), p.up), (share(c.warning), p.warn), (share(c.down), p.down), (share(c.unknown), p.unknown)]
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

    /// The big number and the two lines beside it.
    func big(_ w: inout CellWriter, _ big: (digits: String, top: String, bottom: String), tone: RGBA, short: Bool, blockHeight: Double) {
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
    }

    /// Direct sources under their state: the servers current as the big
    /// number, then a line per source ending in its servers, or the state
    /// that asks for a look. Without room for the number, its words.
    func sources(_ w: inout CellWriter, _ s: SourceStatusSection, tone: RGBA, short: Bool, blockHeight: Double, rows: Int = 4) {
        let n = w.frame.columns
        if blockHeight > 0 {
            big(&w, s.big, tone: tone, short: false, blockHeight: blockHeight)
        } else {
            w.line([.t(CellText.truncate(s.subtitle, n), p.muted)])
        }
        guard !short else { return }
        sourceRows(&w, s, rows: rows)
    }

    /// A line per source, at most `rows`, ending in its servers or the
    /// state that asks for a look; those left out are counted.
    func sourceRows(_ w: inout CellWriter, _ s: SourceStatusSection, rows: Int) {
        let n = w.frame.columns
        let list = s.value.sources
        for source in list.prefix(rows) {
            let detail = s.detail(source)
            let look = s.needsLook(source)
            let room = n - CellText.width(detail) - 3
            w.line([.mark(s.mark(source), p), .t(" " + CellText.truncate(source.name, max(1, room)), p.text)],
                   [.t(detail, look ? p.text : p.muted, bold: look)])
        }
        if list.count > rows {
            w.line([.t("  " + CellText.truncate(tr("\(list.count - rows) more in Settings"), n - 2), p.muted)])
        }
    }

    /// The pinned servers' readings, a line each under a line of labels:
    /// CPU, memory and disk as their cards read them, "—" where withheld,
    /// and where there's room a short bar before each. At most `lines`
    /// lines; servers left out are counted on the last.
    func resources(_ w: inout CellWriter, _ cards: [ServerCardModel], lines: Int) {
        let n = w.frame.columns
        let fit = (n - 2 - 12 - 3 * 5) / 3 - 1
        let bar = fit >= 3 ? min(8, fit) : 0
        let column = 4 + (bar > 0 ? bar + 1 : 0)
        let name = max(4, n - 2 - 3 * (column + 1))
        let labels = [tr("CPU"), tr("MEM"), tr("DSK ").trimmingCharacters(in: .whitespaces)]
        w.line([.t(String(repeating: " ", count: 2 + name), p.text)]
               + labels.map { .t(" " + CellText.padLeft($0, column), p.faint) })
        let room = max(0, lines - 1)
        let shown = cards.count <= room ? cards.count : max(0, room - 1)
        for c in cards.prefix(shown) {
            var segs: [Seg] = [.mark(c.mark, p), .t(" " + CellText.pad(CellText.truncate(c.name, name), name), p.text)]
            for m in [c.cpu, c.memory, c.disk] {
                segs.append(.t(" ", p.text))
                if bar > 0 {
                    segs += [.bar(cells: bar, percent: m.percent, limit: m.limit,
                                  color: m.percent.map { p.load($0, limit: m.limit) } ?? p.track, withheld: m.percent == nil),
                             .t(" ", p.text)]
                }
                segs.append(.t(m.percent.map { CellText.padLeft(Words.percent($0, digits: 0), 4) } ?? "   —",
                               m.percent == nil ? p.faint : p.text, bold: m.percent != nil))
            }
            w.line(segs)
        }
        if cards.count > shown { w.line([.t("  " + CellText.truncate(tr("+\(cards.count - shown) more"), n - 2), p.muted)]) }
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
            w.line([.mark(item.mark, p), .t(" " + CellText.route(item.route, n - 3 - CellText.width(st) - 1), p.text, bold: true)],
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

    /// At most `lines` lines: applications left out are counted on the
    /// last, their marks kept, trouble first.
    func applications(_ w: inout CellWriter, _ a: ApplicationsSection, nameWidth: Int = 15, tight: Bool = false, notes: Bool = true,
                      lines: Int = .max) {
        let (shown, rest) = a.cut(lines)
        defer {
            if !rest.isEmpty {
                let per = tight ? 1 : 2
                var segs: [Seg] = [.t("  ", p.text), .t(CellText.pad(tr("+\(rest.count) more"), nameWidth), p.muted), .t(" ", p.text)]
                let room = w.frame.columns - 2 - nameWidth - 1
                let marks = Mark.troubleFirst(rest, by: \.mark)
                let fit = marks.count * per <= room ? marks.count : max(0, (room - 3) / per)
                for r in marks.prefix(fit) {
                    segs.append(.mark(r.mark, p))
                    if !tight { segs.append(.t(" ", p.text)) }
                }
                if fit < marks.count { segs.append(.t("+\(marks.count - fit)", p.faint)) }
                w.line(segs)
            }
        }
        for row in shown {
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

    // MARK: fleet

    /// Two to a line, each column as wide as the other: the provider's logo,
    /// who, and a mark per node at the column's end. Edges and platforms
    /// lead, saying what they are where there's room. At most `lines`
    /// lines: groups left out are counted in the last cell, their nodes'
    /// marks kept, trouble first.
    func fleet(_ w: inout CellWriter, _ f: FleetSection, columns: Int = 2, marks: Int = 4, lines: Int = .max) {
        let gap = 2
        let cw = (w.frame.columns - gap * (columns - 1)) / columns
        func entry(_ lead: [Seg], _ title: String, _ titleColor: RGBA, tag: String, nodes: [FleetSection.Node]) -> [Seg] {
            var tail: [Seg] = nodes.prefix(marks).map { .mark($0.mark, p) }
            if nodes.count > marks { tail.append(.t("+\(nodes.count - marks)", p.faint)) }
            let room = cw - 2 - tail.reduce(0) { $0 + $1.width } - 1
            let fits = !tag.isEmpty && CellText.width(title) + CellText.width(tag) <= room
            var segs = lead + [.t(CellText.truncate(title, max(1, room)), titleColor)]
            if fits { segs.append(.t(tag, p.faint)) }
            let used = segs.reduce(0) { $0 + $1.width } + tail.reduce(0) { $0 + $1.width }
            return segs + [.t(String(repeating: " ", count: max(1, cw - used)), p.text)] + tail
        }
        func entry(_ g: FleetSection.Group) -> [Seg] {
            let logo = Seg.logo(g.provider, kind: g.kind, p)
            return entry(logo.isEmpty ? [.t("  ", p.text)] : logo, g.title, p.text, tag: g.isEdge ? " " + Words.kind(g.kind) : "",
                         nodes: g.nodes)
        }
        // As many groups as fit, a cell for the rest when some don't.
        func rows(_ n: Int) -> Int { (n + columns - 1) / columns }
        func need(_ k: Int) -> Int {
            let e = min(k, f.edges.count)
            return rows(e) + rows(k - e + (k < f.groups.count ? 1 : 0))
        }
        var shown = f.groups.count
        while shown > 0, need(shown) > lines { shown -= 1 }
        let edges = Array(f.edges.prefix(shown))
        var servers = Array(f.servers.prefix(shown - edges.count)).map(entry)
        let rest = Array(f.edges.dropFirst(edges.count) + f.servers.dropFirst(shown - edges.count))
        if !rest.isEmpty {
            servers.append(entry([.t("  ", p.text)], tr("+\(rest.count) more"), p.muted, tag: "", nodes: FleetSection.troubleFirst(rest)))
        }
        // Servers start a line of their own after the edges.
        for part in [edges.map(entry), servers] {
            for row in stride(from: 0, to: part.count, by: columns) {
                var segs: [Seg] = []
                for (k, cell) in part[row..<min(row + columns, part.count)].enumerated() {
                    if k > 0 { segs.append(.t(String(repeating: " ", count: gap), p.text)) }
                    segs += cell
                }
                w.line(segs)
            }
        }
    }

    // MARK: servers

    /// "● [logo] Oracle New York": the TUI leads a node's name with its
    /// provider's logo.
    func serverTitle(_ c: ServerCardModel, prefix: [Seg] = []) -> [Seg] {
        prefix + [.t(" ", p.text), .mark(c.mark, p), .t(" ", p.text)] + Seg.logo(c.isMissing ? "" : c.provider, kind: c.kind, p)
            + [.t(c.name + " ", p.text, bold: true)]
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
                for (i, part) in [Words.kind(c.kind), provider, place].enumerated() where !part.isEmpty {
                    if !segs.isEmpty { segs.append(.t(" · ", p.faint)) }
                    segs.append(.t(part, i == 0 ? p.kind : p.muted))
                }
                if let time { segs += [.t(" · ", p.faint), .t(time, p.text)] }
                return segs
            }
            func width(_ segs: [Seg]) -> Int { segs.reduce(0) { $0 + $1.width } }
            // A direct source's server is read from a source, said where
            // a provider would be; with no place beside it, it shortens.
            let provider = c.provider.isEmpty ? c.origin?.detail ?? "" : c.provider
            var segs = line(provider, c.place)
            if width(segs) > room, c.place.isEmpty, !provider.isEmpty {
                segs = line(CellText.truncate(provider, max(1, CellText.width(provider) - (width(segs) - room))), "")
            }
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

    enum ZoneLines {
        /// Its time, places, marks and offset; then its zone name and its
        /// day ribbon.
        case two
        /// Time, places, marks, a ribbon where it fits and the offset.
        case one(ribbon: Bool)
        /// Its time and marks; then its places, a step in, and its offset,
        /// for a column too narrow to hold them beside the time.
        case stacked
    }

    /// Each zone in `lines`, every ribbon as wide as the others so the now
    /// ticks line up. `shown` are the zones that fit, `rest` those left
    /// out, counted on a last line with their servers' marks, trouble
    /// first.
    func zones(_ w: inout CellWriter, _ z: ZonesSection, shown: [ZonesSection.Zone]? = nil, rest: [ZonesSection.Zone] = [],
               lines: ZoneLines = .two, foot: Bool = true) {
        let n = w.frame.columns
        let shown = shown ?? z.zones
        // As wide as the widest clock or zone name ("GMT-10", "GMT+5:30"),
        // and as "12:00 AM", so the column holds still from one minute's
        // entry to the next.
        let tw = shown.map { zone in
            let widest = 5 + (zone.period.isEmpty ? 0 : 1 + CellText.width(zone.period))
            return max(CellText.width(zone.clock), widest, min(CellText.width(zone.zoneName), 9))
        }.max() ?? 0
        let rw = shown.map { max(CellText.width($0.relative), z.isLongPast ? 0 : CellText.width($0.day)) }.max() ?? 0
        // Night is the darker of the palette's quiet tones, day the lighter.
        let dark = p.ink.r + p.ink.g + p.ink.b < 1.5
        let (night, day) = dark ? (p.track, p.muted) : (p.faint, p.track)
        func ribbon(_ zone: ZonesSection.Zone, _ width: Int) -> Seg {
            let cells = (0..<width).map { i in
                night.mix(day, ZonesSection.daylight(ZonesSection.hour(zone, at: (Double(i) + 0.5) / Double(width))))
            }
            return .ribbon(cells, midnights: ZonesSection.midnights(zone), now: p.accent)
        }
        func clock(_ zone: ZonesSection.Zone) -> Seg {
            // Long past its reload, the time isn't known.
            z.isLongPast ? .t(CellText.pad("—", tw), p.faint) : .t(CellText.pad(zone.clock, tw), p.text, bold: true)
        }
        // Every mark in `room` cells, or as many as fit beside a count of
        // the rest, trouble first, so trouble left out still shows.
        func marks(_ servers: [ZonesSection.Server], room: Int) -> [Seg] {
            guard servers.count > room else { return servers.map { .mark($0.mark, p) } }
            var shown = room - 2
            while shown > 0, shown + 1 + String(servers.count - shown).count > room { shown -= 1 }
            guard shown > 0 else { return [.t("+\(servers.count)", p.faint)] }
            let first = Mark.troubleFirst(servers, by: \.mark)
            return first.prefix(shown).map { .mark($0.mark, p) } + [.t("+\(servers.count - shown)", p.faint)]
        }
        let relative = { (zone: ZonesSection.Zone) -> Seg in .t(CellText.padLeft(zone.relative, rw), zone.isHere ? p.accent : p.muted) }
        switch lines {
        case .two:
            let width = max(8, n - tw - 2 - 1 - rw)
            for zone in shown {
                let m = marks(zone.servers, room: 10)
                let room = n - tw - 2 - m.reduce(0) { $0 + $1.width } - 1 - rw - 1
                w.line([clock(zone), .t("  ", p.text), .t(CellText.truncate(zone.title, max(1, room)), p.text)],
                       m + [.t(" ", p.text), relative(zone)])
                // Long past a reload, its now would be an hour gone by.
                w.line([.t(CellText.pad(CellText.truncate(zone.zoneName, tw), tw), p.faint), .t("  ", p.text)]
                       + (z.isLongPast ? [] : [ribbon(zone, width)]),
                       z.isLongPast ? [] : [.t(CellText.padLeft(zone.day, rw), p.faint)])
            }
        case .one(let withRibbon):
            // Places take what they need, leaving the ribbon eight cells,
            // and at least ten; the ribbon takes the rest.
            let markCells = shown.map { marks($0.servers, room: 8).reduce(0) { $0 + $1.width } }.max() ?? 0
            let both = n - tw - 1 - 1 - markCells - 1 - 1 - rw
            let places = shown.map { CellText.width($0.title) }.max() ?? 0
            let ribbonCells = withRibbon && !z.isLongPast ? both - min(places, max(10, both - 8)) : 0
            for zone in shown {
                let m = marks(zone.servers, room: 8)
                var right: [Seg] = m + [.t(String(repeating: " ", count: markCells - m.reduce(0) { $0 + $1.width }), p.text)]
                if ribbonCells >= 6 { right += [.t(" ", p.text), ribbon(zone, ribbonCells)] }
                if withRibbon { right += [.t(" ", p.text), relative(zone)] }
                let room = n - tw - 1 - right.reduce(0) { $0 + $1.width } - 1
                w.line([clock(zone), .t(" ", p.text), .t(CellText.truncate(zone.title, max(1, room)), p.text)], right)
            }
        case .stacked:
            for zone in shown {
                w.line([clock(zone)], marks(zone.servers, room: max(1, n - tw - 1)))
                w.line([.t("  " + CellText.truncate(zone.title, max(1, n - 2 - 1 - rw)), p.text)], [relative(zone)])
            }
        }
        guard foot else { return }
        if !rest.isEmpty {
            w.line([.t(tr("+\(rest.count) more"), p.muted)], marks(ZonesSection.servers(rest), room: 12))
        } else if !z.isCurrent, shown.count < z.zones.count + 1 {
            w.line([.mark(.offline, p), .t(" " + tr("servers not known now"), p.muted)])
        } else if z.unplaced > 0 {
            w.line([.t(tr("\(z.unplaced) without a time zone"), p.faint)])
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

    // MARK: map

    /// The map in `rows` lines, then what it can't place, counted with
    /// their marks, trouble first. Returns where the map is.
    @discardableResult
    func map(_ w: inout CellWriter, _ m: MapSection, rows: Int, detail: MapDetail = .places, tray: Bool = true) -> CGRect {
        let n = w.frame.columns
        let rect = CGRect(x: w.frame.x, y: w.y, width: Double(n) * w.cell, height: Double(rows) * w.lineHeight)
        w.items += CellsMap(map: m, p: p, metrics: w.metrics, detail: detail, plain: w.plain)
            .items(x: rect.minX, y: rect.minY, cols: n, rows: rows)
        w.y += rect.height
        if tray { mapTray(&w, m) }
        return rect
    }

    /// Whether the map has a line to say beneath it.
    func mapHasTray(_ m: MapSection) -> Bool { MapFoot.says(m) }

    func mapTray(_ w: inout CellWriter, _ m: MapSection) {
        let n = w.frame.columns
        if m.isTooLarge {
            w.line([.mark(.degraded, p), .t(" " + CellText.truncate(tr("Too large to draw: see the topology in Topophany"), n - 2), p.muted)])
            return
        }
        let unplaced = Mark.troubleFirst(m.unplaced, by: \.mark)
        let note = m.source == .places ? tr("placed by name") : !m.isCurrent ? tr("not current") : ""
        guard !unplaced.isEmpty || !note.isEmpty else { return }
        var segs: [Seg] = []
        if !unplaced.isEmpty {
            segs.append(.t(tr("no location") + " ", p.faint))
            var used = segs.reduce(0) { $0 + $1.width } + CellText.width(note) + 1
            for (i, node) in unplaced.enumerated() {
                let name = node.name + "  "
                let rest = unplaced.count - i
                if used + 2 + CellText.width(name) + (rest > 1 ? 4 : 0) > n {
                    segs += [.t("+\(rest)", p.faint)]
                    break
                }
                segs += [.mark(node.mark, p), .t(" " + name, p.muted)]
                used += 2 + CellText.width(name)
            }
        }
        w.line(segs, note.isEmpty ? [] : [.t(note, p.faint)])
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover: String?
    @State private var position = ScrollPosition(edge: .top)
    @State private var leapState = PanelScrollState()

    static let columns = 48
    nonisolated static let radius = 12.0

    var body: some View {
        let scene = Self.scene(model, ctx: ctx, focusFirstAttention: focusFirstAttention, hover: hover, drawsLeapDirection: false)
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let p = CellsPalette(ctx.theme)
        fitted(scene)
            .background {
                shape.fill(Color(p.ink))
                TextureFill(texture: p.texture, color: Color(p.grain)).clipShape(shape)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(CellsPalette(ctx.theme).line.opacity(ctx.increaseContrast ? 1 : 0.85)), lineWidth: 1))
            .overlay(shape.stroke(Color.black.opacity(ctx.theme.appearance == .light ? 0.22 : 0.7), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CellsAccessibility.panel(model))
            .overlay(alignment: .bottomLeading) { keys(scene) }
            .overlay(alignment: .topLeading) { quietKey(scene) }
            .overlay(alignment: .topLeading) { downloadKey(scene) }
    }

    /// The keycaps are buttons too, and `,`, `q` and `m` work alone, as the
    /// panel shows them. The footer is always at the bottom.
    func keys(_ scene: CellScene) -> some View {
        ZStack(alignment: .bottomLeading) {
            key(scene, "open", tr("Open in Terminal"), nil) { actions.openTerminal() }
            key(scene, "settings", tr("Settings"), KeyboardShortcut(",", modifiers: [])) { actions.openSettings() }
            key(scene, "quit", tr("Quit"), KeyboardShortcut("q", modifiers: [])) { actions.quit() }
            if let rect = scene.regions["leap"], let direction = scene.regions["leapDirection"] {
                CellsLeapKey(state: leapState, metrics: scene.metrics, rect: rect, direction: direction,
                             color: hover == "leap" ? CellsPalette(ctx.theme).text : CellsPalette(ctx.theme).muted,
                             action: leap)
                    .onHover { inside in
                        if inside { hover = "leap" } else if hover == "leap" { hover = nil }
                    }
                    .offset(x: rect.minX, y: rect.maxY - scene.size.height)
            }
        }
    }

    /// About half the panel down, or from the end back to the top.
    func leap() {
        guard let panel = ctx.maxHeight else { return }
        let y = leapState.target(panel: panel)
        withAnimation(leapState.animation(panel: panel, reduceMotion: reduceMotion)) { position.scrollTo(y: y) }
    }

    /// Status's keycap, from the top: Status stays put while the rest
    /// scrolls. A shortcut keeps the action it was first given, so the
    /// action asks the app which way to turn.
    func quietKey(_ scene: CellScene) -> some View {
        key(scene, "quiet", model.alert == .quiet ? tr("Show the menu bar’s colors again") : tr("Quiet the menu bar until this gets worse"),
            KeyboardShortcut("m", modifiers: []), fromTop: true) { actions.toggleQuiet() }
    }

    /// `d` downloads topo while none can run.
    func downloadKey(_ scene: CellScene) -> some View {
        key(scene, "download", model.download?.title ?? "", KeyboardShortcut("d", modifiers: []), fromTop: true) {
            if let d = model.download, !d.isDownloading { actions.download(d.build) }
        }
    }

    @ViewBuilder
    func key(_ scene: CellScene, _ id: String, _ label: String, _ shortcut: KeyboardShortcut?, fromTop: Bool = false,
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
                .offset(x: r.minX, y: fromTop ? r.minY : r.maxY - scene.size.height)
        }
    }

    /// The whole scene, or, when it is taller than the screen allows, the
    /// header, Status (when pinned) and footer fixed and the rest scrolling,
    /// the keyboard's focus kept in view.
    @ViewBuilder func fitted(_ scene: CellScene) -> some View {
        let h = scene.size.height
        if let maxH = ctx.maxHeight, h > maxH,
           let header = scene.marks["header"], let status = scene.marks["status"], let footer = scene.marks["footer"] {
            let top = model.pinStatus ? status : header
            VStack(spacing: 0) {
                slice(scene, top: 0, bottom: top)
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        slice(scene, top: top, bottom: footer)
                            .overlay(alignment: .topLeading) { focusAnchor(scene, top: top, bottom: footer) }
                    }
                    .scrollIndicators(.never)
                    .scrollPosition($position)
                    .onScrollGeometryChange(for: PanelLeap.self, of: PanelLeap.init) { _, new in leapState.update(new) }
                    .frame(height: max(80, maxH - top - (h - footer)))
                    .onChange(of: ctx.focus) { _, focus in
                        guard let focus else { return }
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo(focus) }
                    }
                    .onChange(of: ctx.leaps) { leap() }
                }
                slice(scene, top: footer, bottom: h)
            }
            .frame(width: scene.size.width)
        } else {
            CellCanvas(scene: scene).overlay(alignment: .topLeading) { live(scene, top: 0, bottom: scene.size.height) }
        }
    }

    /// The map as it moves, where a band from `top` to `bottom` shows it.
    @ViewBuilder func live(_ scene: CellScene, top: Double, bottom: Double) -> some View {
        if let m = model.map, let r = scene.regions["map"], r.maxY > top, r.minY < bottom {
            CellsMapLive(map: m, scene: scene, rect: r, meta: scene.regions["mapMeta"],
                         p: CellsPalette(ctx.theme))
        }
    }

    /// An empty view where the focus is drawn, for the scroll to bring
    /// into view, a line's breadth of the scroll's edges kept clear.
    @ViewBuilder func focusAnchor(_ scene: CellScene, top: Double, bottom: Double) -> some View {
        if let focus = ctx.focus, let r = scene.regions["focus"], r.minY >= top, r.maxY <= bottom {
            let margin = scene.metrics.line
            let y = max(0, r.minY - top - margin)
            VStack(spacing: 0) {
                Color.clear.frame(width: 1, height: y)
                Color.clear.frame(width: 1, height: min(bottom - top - y, r.height + 2 * margin)).id(focus)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A band of the scene, from `top` to `bottom`. Clipping only hides the
    /// rest of the scene; the band's shape also keeps it from taking the
    /// clicks and scrolls meant for the bands beside it.
    func slice(_ scene: CellScene, top: Double, bottom: Double) -> some View {
        CellCanvas(scene: scene.band(top: top, bottom: bottom))
            .overlay(alignment: .topLeading) { live(scene, top: top, bottom: bottom) }
            .offset(y: -top)
            .frame(width: scene.size.width, height: bottom - top, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
    }

    /// - Parameter leapUp: whether the scroll is at its end, and the quick
    ///   scroll's keycap points back up.
    static func scene(_ model: PanelModel, ctx: RenderContext, focusFirstAttention: Bool = false, hover: String? = nil,
                      leapUp: Bool = false, drawsLeapDirection: Bool = true) -> CellScene {
        let m = CellMetrics.panel
        let p = CellsPalette(ctx.theme)
        let width = Double(columns) * m.cell + 14
        var w = CellWriter(metrics: m, palette: p, width: width, frame: .init(x: 7, columns: columns))
        let b = CellsBodies(p: p, focus: ctx.focus)
        let ch = model.chrome

        // Header: the TUI's top bar, or on a printed page a masthead over a
        // double rule.
        if p.box == .rules {
            w.items.append(.fill(CGRect(x: 6, y: 25, width: width - 12, height: 1), p.line, radius: 0))
            w.items.append(.fill(CGRect(x: 6, y: 27.5, width: width - 12, height: 0.75), p.line, radius: 0))
        } else {
            w.items.append(.fill(CGRect(x: 0, y: 0, width: width, height: 28), p.inkHigh, radius: 0))
            w.items.append(.fill(CGRect(x: 0, y: 27, width: width, height: 1), p.line.opacity(0.7), radius: 0))
        }
        w.y = 5
        let live: [Seg] = ch.isLive ? [.mark(.up, p), .t(" " + tr("LIVE"), p.up, bold: true)]
            : [.mark(.offline, p), .t(" " + tr("OFFLINE"), p.down, bold: true)]
        let head = CellText.truncate(ch.view, columns - 26 - CellText.width(ch.project))
        w.line([.glyph(.logo, p.accent), .t(" TOPOPHANY", p.accent, bold: true), .t(" ╱ ", p.faint), .t(ch.project, p.text, bold: true),
                .t(" · " + head, p.faint)], live)
        w.y = 28

        var marks = ["header": w.y]
        var regions: [String: CGRect] = [:]
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
        // Below the verdict, `m` quiets the menu bar's alert, or shows it
        // again; while no topo can run, `d` downloads one.
        var quietRegion: CGRect?
        var downloadRegion: CGRect?
        w.box(title(tr("STATUS")), [.t(" " + age + " ", p.muted)],
              x0: x0, x1: x1, style: .panel, tint: b.statusTint(st)) { w in
            b.status(&w, st, blockHeight: 54)
            func keycap(_ k: String, _ words: String, _ id: String) -> CGRect {
                let text = " " + CellText.truncate(words, w.frame.columns - 4)
                w.y += 4
                let r = CGRect(x: w.frame.x - 2, y: w.y - 4, width: Double(3 + CellText.width(text)) * w.cell + 4, height: w.lineHeight + 8)
                w.line([.key(" \(k) "), .t(text, hover == id ? p.text : p.muted)])
                return r
            }
            if model.alert != .unavailable {
                quietRegion = keycap("m", model.alert == .quiet ? tr("menu bar quiet until it gets worse · undo")
                                                                : tr("quiet the menu bar until it gets worse"), "quiet")
            }
            if let d = model.download { downloadRegion = keycap("d", d.keyWords, "download") }
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
            case .services(let cards):
                for c in cards {
                    w.box(b.serviceTitle(c), b.servicePill(c), x0: x0, x1: x1, style: .panel) { b.service(&$0, c) }
                }
            case .map(let m):
                w.box(title(tr("MAP")), [.t(" " + tr("\(m.places.count) places") + " ", p.muted)], x0: x0, x1: x1, style: .panel) {
                    regions["map"] = b.map(&$0, m, rows: 9)
                }
                regions["mapMeta"] = w.titleRight
                if ctx.focus == "map", let r = regions["map"] {
                    // The accent's bar a focused row has, down the map's left.
                    w.focused = r
                    w.items.append(.fill(CGRect(x: r.minX - w.cell + 1, y: r.minY, width: 2, height: r.height), p.accent, radius: 0))
                }
            case .fleet(let f):
                w.box(title(tr("FLEET"), "\(f.nodeCount)"), f.providerCount > 0 ? [.t(" " + tr("\(f.providerCount) providers") + " ", p.muted)] : [],
                      x0: x0, x1: x1, style: .panel) { b.fleet(&$0, f) }
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
        var keys = [key("↵", tr("Open"), "open"), key(",", tr("Settings"), "settings"), key("q", tr("Quit"), "quit")]
        // While the panel scrolls, space leaps about half the panel down,
        // or from the end back to the top.
        if let maxH = ctx.maxHeight, footTop + 28 > maxH {
            keys.append(key("␣", drawsLeapDirection ? (leapUp ? "↑" : "↓") : " ", "leap"))
        }
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
        if p.box == .rules {
            w.items.append(.fill(CGRect(x: 6, y: footTop, width: width - 12, height: 0.75), p.line, radius: 0))
        } else {
            w.items.append(.fill(CGRect(x: 0, y: footTop, width: width, height: footHeight), p.inkHigh, radius: 0))
            w.items.append(.fill(CGRect(x: 0, y: footTop, width: width, height: 1), p.line.opacity(0.7), radius: 0))
        }
        w.y = footTop + 5
        if ownLine {
            w.line([conn])
            w.y += 2
        }
        // Each keycap and its label is a button.
        regions["quiet"] = quietRegion
        regions["download"] = downloadRegion
        regions["focus"] = w.focused
        var col = 0
        for k in keys {
            let n = k.segs.reduce(0) { $0 + $1.width }
            regions[k.id] = CGRect(x: w.frame.x + Double(col) * w.cell - 2, y: w.y - 4, width: Double(n - 2) * w.cell + 4, height: w.lineHeight + 8)
            if k.id == "leap" {
                regions["leapDirection"] = CGRect(x: w.frame.x + Double(col + 4) * w.cell, y: w.y,
                                                 width: w.cell, height: w.lineHeight)
            }
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

/// Only this one-cell drawing observes the scroll's edge. Rebuilding the
/// entire scene when a return leaves the bottom interrupts its first frames.
private struct CellsLeapKey: View {
    var state: PanelScrollState
    var metrics: CellMetrics
    var rect: CGRect
    var direction: CGRect
    var color: RGBA
    var action: () -> Void

    var body: some View {
        let up = state.atEnd
        Button(action: action) {
            Canvas { ctx, _ in
                CellCanvas.draw([.text(x: direction.minX - rect.minX, y: direction.minY - rect.minY,
                                       up ? "↑" : "↓", color, bold: false)], in: &ctx, metrics: metrics)
            }
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(up ? tr("Back to top") : tr("Scroll down"))
    }
}

/// What VoiceOver reads for a cell scene: the same words, as sentences.
enum CellsAccessibility {
    static func panel(_ m: PanelModel) -> String {
        var parts = [m.status.title, m.download?.line ?? m.status.subtitle]
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
