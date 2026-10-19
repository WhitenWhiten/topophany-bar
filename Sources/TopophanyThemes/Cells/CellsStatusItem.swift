import SwiftUI
import TopophanySections

/// The Terminal menu bar item: a chip of the TUI's ink with its glyph and
/// words, `✖ 5 INCIDENTS`. It paints its own ink on any menu bar.
///
/// It moves as the TUI does. While what it shows is current the glyph
/// breathes toward the glow, as the TUI's live dot does; while `topo`
/// starts, the TUI's spinner turns in its place. New words type themselves
/// in, and a change that needs more attention lights the chip's edge once.
struct CellsStatusItem: View {
    var model: StatusItemModel
    var ctx: StatusItemContext

    static let metrics = CellMetrics(fontSize: 11, line: 18)
    /// The TUI's spinner, a frame every 90 ms.
    static let spinner: [UInt8] = [0x0B, 0x19, 0x39, 0x38, 0x3C, 0x34, 0x26, 0x27, 0x07, 0x0F]
    static let pad = 7.0

    /// The latest change, while it settles.
    var change: StatusItemMotion.Change? {
        guard ctx.motion.moves, let c = ctx.motion.change, c.age < StatusItemMotion.changeLength else { return nil }
        return c
    }

    var body: some View {
        let p = CellsPalette(ctx.theme)
        let text = model.tuiText.isEmpty ? "" : " " + model.tuiText
        return CellsChip(segments: [glyph(p)] + words(text, p), ctx: ctx, flash: Color(p.tone(model.mark)).opacity(flash))
            .accessibilityLabel(Text(model.accessibilityLabel))
    }

    /// The mark, breathing while live; the spinner while `topo` starts.
    func glyph(_ p: CellsPalette) -> Seg {
        if model.activity == .connecting, ctx.motion.moves {
            let frame = Int((ctx.motion.time / 0.09).rounded(.down)) % Self.spinner.count
            return .glyph(.braille(Self.spinner[max(0, frame)]), p.accent2)
        }
        let tone = model.statusColors ? p.tone(model.mark) : p.muted
        // Whole steps of the turn are the tone itself.
        let breath = (1 - cos(2 * .pi * ctx.motion.turn)) / 4
        return .glyph(.mark(model.mark), tone.mix(p.glow, breath))
    }

    /// The words, typed in after a change, a cursor ahead of them.
    func words(_ text: String, _ p: CellsPalette) -> [Seg] {
        guard let ch = change, ch.from.tuiText != model.tuiText, !text.isEmpty else { return [.t(text, p.text, bold: true)] }
        let chars = Array(text)
        let shown = Int((Ease.span(ch.age, 0.04, 0.32) * Double(chars.count)).rounded(.up))
        guard shown < chars.count else { return [.t(text, p.text, bold: true)] }
        let typed = String(chars.prefix(shown))
        let rest = CellText.width(text) - CellText.width(typed)
        return [.t(typed, p.text, bold: true), .t("▌", p.accent), .t(String(repeating: " ", count: max(0, rest - 1)), p.text)]
    }

    /// How brightly the edge lights after a change that needs more
    /// attention.
    var flash: Double {
        guard let ch = change, model.needsMoreAttention(than: ch.from) else { return 0 }
        return 0.9 * pow(1 - Ease.span(ch.age, 0, StatusItemMotion.changeLength), 1.5)
    }

}

/// A chip of the TUI's ink holding one line of cells.
struct CellsChip: View {
    var segments: [Seg]
    var ctx: StatusItemContext
    /// Lights the edge, fading to clear.
    var flash: Color = .clear

    var body: some View {
        let p = CellsPalette(ctx.theme)
        let m = CellsStatusItem.metrics
        let pad = CellsStatusItem.pad
        let cells = segments.reduce(0) { $0 + $1.width }
        let width = Double(cells) * m.cell + 2 * pad
        var w = CellWriter(metrics: m, palette: p, width: width, frame: .init(x: pad, columns: cells))
        w.draw(segments, x: pad, y: 0)
        let scene = CellScene(size: CGSize(width: width, height: m.line), metrics: m, items: w.items)
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return CellCanvas(scene: scene)
            .background(shape.fill(Color(p.ink)))
            .overlay(shape.strokeBorder(ctx.menuBarIsDark ? Color(p.accent).opacity(0.26) : Color(p.ink).opacity(0.5), lineWidth: 1))
            .overlay(shape.strokeBorder(flash, lineWidth: 1))
            .shadow(color: .black.opacity(ctx.menuBarIsDark ? 0.25 : 0.18), radius: 1, y: 1)
            .padding(.horizontal, 1).padding(.vertical, 2)
    }
}
