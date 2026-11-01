import Foundation
import TopophanySections

extension CellsBodies {
    func monitor(_ w: inout CellWriter, _ card: ServiceCardModel, _ m: MonitorCardModel) {
        let n = w.frame.columns
        focusRow(&w, card.focusID, lines: 2)
        w.line([.t(CellText.truncate(m.subtitle, max(4, n - CellText.width(card.shortAge) - 1)), p.muted)], [.t(card.shortAge, p.faint)])
        for line in CellText.wrap(m.summary, n, lines: 2) { w.line([.t(line, p.text)]) }
        if !m.reading.isEmpty { w.line([.t(CellText.truncate(m.reading, n), p.muted)]) }
        guard m.expanded else { return }
        for check in m.checks.prefix(8) {
            w.line([.dashes(n, p.faint)])
            // A link's only check is the card itself: its name and source add nothing.
            if m.pin.kind == .link, m.checks.count > 1 {
                w.line([.mark(check.mark, p), .t(" " + CellText.truncate(check.name, n - 2), p.text, bold: true)])
                w.line([.t(CellText.truncate(check.source, n), p.faint)])
            }
            if check.summary != m.summary { for line in CellText.wrap(check.summary, n, lines: 2) { w.line([.t(line, p.muted)]) } }
            if !check.reading.isEmpty && check.reading != m.reading { w.line([.t(CellText.truncate(check.reading, n), p.muted)]) }
            fields(&w, check.fields, n)
            if !check.code.isEmpty { w.line([.t(CellText.truncate(check.code, n), p.faint)]) }
            if case .samples = check.history {
                let latency = check.p50.map { check.p50Label + " " + Words.ms($0) } ?? ""
                w.line([.samples(check.history, cells: max(4, n - CellText.width(latency) - 1))], [.t(latency, p.muted)])
            }
        }
        if m.checks.count > 8 { w.line([.t(CellText.truncate(tr("\(m.checks.count - 8) more in Topophany"), n), p.faint)]) }
    }

    /// "label value" pairs side by side, two cells apart, while they fit
    /// the line; one too long for any line is cut to it.
    func fields(_ w: inout CellWriter, _ fields: [MonitorCardModel.Field], _ n: Int) {
        var line: [Seg] = [], used = 0
        for field in fields {
            let label = CellText.width(field.label) + 1
            let value = CellText.truncate(field.value, max(4, n - label))
            let width = label + CellText.width(value)
            if used > 0, used + 2 + width > n {
                w.line(line)
                line = []; used = 0
            }
            if used > 0 { line.append(.t("  ", p.faint)); used += 2 }
            line += [.t(field.label + " ", p.faint), .t(value, p.muted)]
            used += width
        }
        if !line.isEmpty { w.line(line) }
    }
}
