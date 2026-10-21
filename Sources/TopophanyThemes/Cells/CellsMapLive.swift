import SwiftUI
import TopophanyKit
import TopophanySections

/// The Terminal panel's map as it moves. The scene draws the map framed;
/// magnified or moved, this draws it again over the scene's, on the
/// panel's own ground and grain. It takes the map's gestures, as the cards'
/// map does. Laid over the whole scene, in its coordinates, each part
/// placed by padding so the
/// map's frame, which the app's scroll wheel finds it by, is where it shows.
struct CellsMapLive: View {
    var map: MapSection
    var scene: CellScene
    /// Where the map is, and where its count of places is, which the
    /// keys take while it's selected.
    var rect: CGRect
    var meta: CGRect?
    var p: CellsPalette
    @Environment(\.mapViewport) private var viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragged: CGSize = .zero
    @State private var pinch = 1.0

    var cells: CellsMap { CellsMap(map: map, p: p, metrics: scene.metrics) }
    var cols: Int { Int((rect.width / scene.metrics.cell).rounded()) }
    var rows: Int { Int((rect.height / scene.metrics.line).rounded()) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let viewport {
                drawn(viewport)
                gestures(viewport)
            }
        }
        .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
    }

    /// The map as magnified, over the scene's, and while it's selected
    /// what the keys do.
    @ViewBuilder func drawn(_ v: MapViewport) -> some View {
        let t = v.transform
        let m = scene.metrics
        if t != .identity {
            ZStack {
                Color(p.ink)
                TextureFill(texture: p.texture, color: Color(p.grain))
            }
            .frame(width: scene.size.width, height: scene.size.height)
            .mask(alignment: .topLeading) {
                Rectangle().frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
            }
            .allowsHitTesting(false)
        }
        if t != .identity || v.isSelected {
            let items = t == .identity ? [] : cells.items(x: rect.minX, y: rect.minY, cols: cols, rows: rows, transform: t)
            Canvas(rendersAsynchronously: false) { ctx, _ in
                CellCanvas.draw(items + (v.isSelected ? hint : []), in: &ctx, metrics: m)
            }
            .frame(width: scene.size.width, height: scene.size.height)
            .allowsHitTesting(false)
        }
    }

    /// Selected: the accent's bar down the map's left, as a focused row
    /// has, and the keys in its border where it counts its places.
    var hint: [CellItem] {
        let m = scene.metrics
        var items: [CellItem] = [.fill(CGRect(x: rect.minX - m.cell + 1, y: rect.minY, width: 2, height: rect.height), p.accent, radius: 0)]
        if let meta {
            let words = " " + tr("↑ ↓ zoom · esc") + " "
            let w = Double(CellText.width(words)) * m.cell
            items.append(.fill(CGRect(x: min(meta.minX, meta.maxX - w), y: meta.minY, width: max(w, meta.width), height: meta.height),
                               p.ink, radius: 0))
            items.append(.text(x: meta.maxX - w, y: meta.minY, words, p.accent, bold: false))
        }
        return items
    }

    func gestures(_ v: MapViewport) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { g in
                    v.pan(by: CGSize(width: g.translation.width - dragged.width, height: g.translation.height - dragged.height))
                    dragged = g.translation
                }
                .onEnded { _ in dragged = .zero })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { g in
                    v.zoom(by: g.magnification / pinch, at: g.startLocation)
                    pinch = g.magnification
                }
                .onEnded { _ in pinch = 1 })
            .onTapGesture(count: 2) { v.reset(easing: MapViewport.easing(reduceMotion: reduceMotion)) }
            .onTapGesture { v.isSelected = true }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { v.frame = $0 }
            .onAppear { v.layout(CGSize(width: cols * 2, height: rows * 4), unit: CGSize(width: cells.dotW, height: cells.dotH)) }
            .onChange(of: rect.size) { v.layout(CGSize(width: cols * 2, height: rows * 4), unit: CGSize(width: cells.dotW, height: cells.dotH)) }
            .onChange(of: map.frame) { v.reset() }
            .accessibilityElement()
            .accessibilityLabel(MapWords.summary(map))
            .accessibilityAction(named: tr("Zoom In")) { v.step(in: true) }
            .accessibilityAction(named: tr("Zoom Out")) { v.step(in: false) }
            .accessibilityAction(named: tr("Show Every Place")) { v.reset() }
            .padding(.leading, rect.minX).padding(.top, rect.minY)
    }
}
