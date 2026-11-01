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
            if m.pin.kind == .link {
            w.line([.mark(check.mark, p), .t(" " + CellText.truncate(check.name, n - 2), p.text, bold: true)])
            w.line([.t(CellText.truncate(check.source, n), p.faint)])
            }
            if check.summary != m.summary { for line in CellText.wrap(check.summary, n, lines: 2) { w.line([.t(line, p.muted)]) } }
            if !check.reading.isEmpty && check.reading != m.reading { w.line([.t(CellText.truncate(check.reading, n), p.muted)]) }
            for field in check.fields {
                w.line([.t(field.label + " ", p.faint), .t(CellText.truncate(field.value, max(4, n - CellText.width(field.label) - 1)), p.muted)])
            }
            if !check.code.isEmpty { w.line([.t(CellText.truncate(check.code, n), p.faint)]) }
            if case .samples = check.history {
                let latency = check.p50.map { check.p50Label + " " + Words.ms($0) } ?? ""
                w.line([.samples(check.history, cells: max(4, n - CellText.width(latency) - 1))], [.t(latency, p.muted)])
            }
        }
        if m.checks.count > 8 { w.line([.t(CellText.truncate(tr("\(m.checks.count - 8) more in Topophany"), n), p.faint)]) }
    }
}
