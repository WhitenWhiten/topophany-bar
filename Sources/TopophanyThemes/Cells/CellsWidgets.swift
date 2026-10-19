import Foundation
import SwiftUI
import TopophanySections

/// The Terminal widgets: the TUI's boxes at 11 pt, from the same bodies as
/// the panel (DESIGN.md §7.1). Monochrome drops the borders for plain
/// headings (§7.4).
struct CellsWidget: View {
    var model: WidgetModel
    var size: WidgetSize
    var bounds: CGSize
    var ctx: RenderContext

    var body: some View {
        CellCanvas(scene: Self.scene(model, size: size, bounds: bounds, ctx: ctx))
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(CellsAccessibility.panel(model.panel)))
    }

    nonisolated static let pad = (top: 8.0, side: 10.0)

    static func scene(_ model: WidgetModel, size: WidgetSize, bounds: CGSize, ctx: RenderContext) -> CellScene {
        let m = CellMetrics.widget
        let p = CellsPalette(ctx.theme)
        let cols = Int(((bounds.width - 2 * pad.side) / m.cell).rounded(.down))
        var w = CellWriter(metrics: m, palette: p, width: bounds.width, frame: .init(x: pad.side, columns: cols))
        w.plain = ctx.widgetRendering == .vibrant
        w.y = pad.top
        var l = Layout(w: w, b: CellsBodies(p: p, focus: nil), p: p, model: model, ctx: ctx, cols: cols)
        switch model.kind {
        case .status: l.status(size)
        case .server: l.server(size)
        }
        return CellScene(size: bounds, metrics: m, items: l.w.items, live: l.w.live)
    }

    /// Lays out one widget, top to bottom.
    struct Layout {
        var w: CellWriter
        var b: CellsBodies
        var p: CellsPalette
        var model: WidgetModel
        var ctx: RenderContext
        var cols: Int

        var cell: Double { w.cell }
        var style: CellWriter.BoxStyle { .widget }
        var status: StatusSection { model.status }

        /// The x of a column's left edge, from the widget's left padding.
        func x(_ col: Int) -> Double { pad.side + Double(col) * cell }

        func title(_ t: String, _ extra: String? = nil) -> [Seg] {
            var s: [Seg] = [.t(" " + t, p.accent, bold: true)]
            if let extra { s += [.t(" · ", p.faint), .t(extra, p.muted)] }
            return s + [.t(" ", p.text)]
        }

        /// "◉ homelab ……… ● LIVE"
        mutating func head(_ columns: Int) {
            let ch = model.panel.chrome
            let live: [Seg] = ch.isLive && model.isCurrent ? [.mark(.up, p), .t(" " + tr("LIVE"), p.up, bold: true)] : [.mark(.offline, p)]
            let name = ch.project.isEmpty ? "Topophany" : ch.project
            w.line([.glyph(.logo, p.accent), .t(" " + CellText.truncate(name, columns - 10), p.text, bold: true)], live,
                   in: .init(x: pad.side, columns: columns))
        }

        /// The age a box's title border shows, counting up in a widget.
        mutating func ageBox(_ titleSegs: [Seg], at date: Date?, x0: Double, x1: Double, tint: RGBA? = nil,
                             body: (inout CellWriter) -> Void) {
            let top = w.y + (w.plain ? style.margin * 0.4 : style.margin)
            let rightEnd = w.plain ? x1 : x1 - cell + 2
            let titleY = w.plain ? top : top + 1 - style.titleRise
            var right: [Seg] = []
            if let date {
                if ctx.liveDates {
                    w.live.append(LiveAge(right: rightEnd, y: titleY, date: date, color: p.muted, background: w.plain ? nil : p.ink))
                } else {
                    right = [.t(" " + Words.span(since: date, now: status.now) + " ", p.muted)]
                }
            }
            w.box(titleSegs, right, x0: x0, x1: x1, style: style, tint: tint, body: body)
        }

        var updated: Date? { status.isBlind ? status.lastKnown?.at ?? status.updatedAt : status.updatedAt }

        mutating func statusBox(x0: Double, x1: Double, short: Bool) {
            let b = self.b
            let st = status
            ageBox(title(tr("STATUS")), at: updated, x0: x0, x1: x1, tint: b.statusTint(st)) { w in
                b.status(&w, st, short: short, blockHeight: 48)
            }
        }

        mutating func seenBox(x0: Double, x1: Double) {
            guard let seen = model.panel.seen else { return }
            let b = self.b
            w.box(title(tr("SEEN FROM"), seen.total.map { "\($0)" }), x0: x0, x1: x1, style: style) { b.seen(&$0, seen, max: 2) }
        }

        var attention: AttentionSection? { model.panel.attention.flatMap { $0.items.isEmpty ? nil : $0 } }

        mutating func attentionBox(_ a: AttentionSection, x0: Double, x1: Double) {
            let b = self.b
            w.box(title(tr("NEEDS ATTENTION"), "\(a.total)"), x0: x0, x1: x1, style: style) { b.attention(&$0, a, limit: 3, compact: true) }
        }

        mutating func servicesBox(_ a: ApplicationsSection, x0: Double, x1: Double, narrow: Bool) {
            let b = self.b
            w.box(title(tr("SERVICES"), tr("\(a.rows.count) apps")), x0: x0, x1: x1, style: style) {
                b.applications(&$0, a, nameWidth: narrow ? 13 : 15, tight: narrow, notes: !narrow)
            }
        }

        /// Needs attention, or Services when nothing needs attention.
        mutating func rightBox(x0: Double, x1: Double, narrow: Bool) {
            switch (model.right, attention, model.panel.applications) {
            case (.applications, _, let a?), (.automatic, nil, let a?): servicesBox(a, x0: x0, x1: x1, narrow: narrow)
            case (_, let a?, _): attentionBox(a, x0: x0, x1: x1)
            default: break
            }
        }

        // MARK: Status

        mutating func status(_ size: WidgetSize) {
            let x0 = pad.side, x1 = pad.side + Double(cols) * cell
            head(cols)
            switch size {
            case .small:
                statusBox(x0: x0, x1: x1, short: true)
            case .medium:
                let split = x(22)
                let top = w.y
                statusBox(x0: x0, x1: split, short: true)
                w.y = top
                rightBox(x0: split + cell, x1: x1, narrow: true)
            case .large:
                statusBox(x0: x0, x1: x1, short: false)
                seenBox(x0: x0, x1: x1)
                rightBox(x0: x0, x1: x1, narrow: false)
            case .extraLarge:
                let split = x(54)
                let top = w.y
                statusBox(x0: x0, x1: split, short: false)
                seenBox(x0: x0, x1: split)
                if let c = model.panel.servers.first {
                    let b = self.b
                    w.box(b.serverTitle(c), b.serverPill(c), x0: x0, x1: split, style: style) { b.server(&$0, c, bar: 23) }
                }
                w.y = top
                if let a = attention {
                    attentionBox(a, x0: split + cell, x1: x1)
                    if let apps = model.panel.applications { servicesBox(apps, x0: split + cell, x1: x1, narrow: false) }
                } else if let apps = model.panel.applications {
                    servicesBox(apps, x0: split + cell, x1: x1, narrow: false)
                }
            }
        }

        // MARK: Server

        var card: ServerCardModel {
            if let c = model.server { return c }
            let node = if case .server(let n, _) = model.kind { n } else { "" }
            let none = ServerCardModel.Meter(percent: nil, limit: nil, detail: "")
            return ServerCardModel(id: node, name: node.isEmpty ? tr("no server chosen") : node, kind: "", provider: "",
                                   place: node.isEmpty ? tr("choose one in Edit Widget") : tr("not received yet"),
                                   mark: .offline, pill: .cached, isWithheld: true, isMissing: true, cpu: none, memory: none,
                                   disk: none, services: [], servicesSummary: "", observes: [], sampledAt: nil, now: status.now)
        }

        mutating func server(_ size: WidgetSize) {
            let c = card
            let x0 = pad.side, x1 = pad.side + Double(cols) * cell
            let b = self.b
            if size == .small {
                w.line([.mark(c.isWithheld ? .offline : c.mark, p), .t(" " + CellText.truncate(c.name, cols - 2), p.text, bold: true)])
                let kind = c.kind.isEmpty ? tr("NODE") : c.kind.uppercased()
                let p = self.p
                let live = ctx.liveDates
                var ages: [LiveAge] = []
                w.box(title(kind), b.serverPill(c), x0: x0, x1: x1, style: style) { w in
                    let n = w.frame.columns
                    func row(_ label: String, _ m: ServerCardModel.Meter) {
                        let v = m.percent.map { CellText.padLeft(Words.percent($0, digits: 0), 4) } ?? "   —"
                        w.line([.t(label, p.muted), .t(v, m.percent == nil ? p.faint : p.text, bold: m.percent != nil), .t(" ", p.text),
                                .bar(cells: n - 9, percent: m.percent, limit: m.limit,
                                     color: m.percent.map { p.load($0, limit: m.limit) } ?? p.track, withheld: m.percent == nil)])
                    }
                    row(tr("CPU "), c.cpu)
                    row(tr("MEM "), c.memory)
                    row(tr("DSK "), c.disk)
                    let place = c.isMissing ? c.place : (c.place.isEmpty ? c.provider : c.place)
                    if let at = c.sampledAt, live {
                        ages.append(LiveAge(right: w.frame.x + Double(n) * w.cell, y: w.y, date: at, color: p.faint, background: nil))
                        w.line([.t(CellText.truncate(place, n - 8), p.muted)])
                    } else {
                        let age = c.sampledAt.map { Words.span(since: $0, now: c.now, style: .compact) } ?? ""
                        w.line([.t(CellText.truncate(place, n - 6), p.muted)], [.t(c.isWithheld && !age.isEmpty ? tr("last \(age)") : age, p.faint)])
                    }
                }
                w.live += ages
            } else {
                head(cols)
                w.box(b.serverTitle(c), b.serverPill(c), x0: x0, x1: x1, style: style) { b.server(&$0, c, bar: 22, observes: true) }
            }
        }
    }
}
