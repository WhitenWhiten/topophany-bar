import SwiftUI
import TopophanySections

/// The Terminal menu bar item: a chip of the TUI's ink with its glyph and
/// words, `✖ 5 INCIDENTS`. It paints its own ink on any menu bar.
struct CellsStatusItem: View {
    var model: StatusItemModel
    var ctx: StatusItemContext

    static let metrics = CellMetrics(fontSize: 11, line: 18)

    var body: some View {
        let p = CellsPalette(ctx.theme)
        let m = Self.metrics
        let text = model.tuiText.isEmpty ? "" : " " + model.tuiText
        let cells = 1 + CellText.width(text)
        let pad = 7.0
        let width = Double(cells) * m.cell + 2 * pad
        let glyph = model.statusColors ? p.tone(model.mark) : p.muted
        let scene = CellScene(size: CGSize(width: width, height: m.line), metrics: m, items: [
            .glyph(x: pad, y: 0, .mark(model.mark), glyph),
            .text(x: pad + m.cell, y: 0, text, p.text, bold: true),
        ])
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        CellCanvas(scene: scene)
            .background(shape.fill(Color(p.ink)))
            .overlay(shape.strokeBorder(ctx.menuBarIsDark ? Color(p.accent).opacity(0.26) : Color(p.ink).opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(ctx.menuBarIsDark ? 0.25 : 0.18), radius: 1, y: 1)
            .padding(.horizontal, 1).padding(.vertical, 2)
            .accessibilityLabel(Text(model.accessibilityLabel))
    }
}
