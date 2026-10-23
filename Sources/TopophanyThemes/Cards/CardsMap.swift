import SwiftUI
import TopophanyKit
import TopophanySections

/// The Map card: the geographic map full width under its title, and
/// below it what the map can't place.
struct CardsMapCard: View {
    var map: MapSection
    var p: CardsPalette
    var t: CardsType
    var focused: Bool
    @Environment(\.mapViewport) private var viewport

    static let height = 172.0

    var body: some View {
        let matte = p.style.surface == .matte
        Card(p: p) {
            HStack(spacing: 6) {
                if p.style.caps {
                    Text(tr("Map").uppercased(with: L10n.locale)).font(t.font(10, .semibold)).tracking(1.4).foregroundStyle(p.accent)
                } else {
                    Image(systemName: "map").font(.system(size: 11.5 * t.scale, weight: .medium)).frame(width: 14)
                    Text(tr("Map")).font(t.font(11.5, .semibold))
                }
                Spacer(minLength: 6)
                // Selected, what the keys do, clear of the map.
                if viewport?.isSelected == true {
                    Text(tr("↑ ↓ zoom · esc")).font(t.font(10, .medium)).foregroundStyle(p.accent).lineLimit(1)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(p.l2)
            .animation(Highlight.easing(viewport?.isSelected == true), value: viewport?.isSelected == true)
            .padding(.bottom, p.style.caps ? 8 : 6)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isHeader)
            MapCanvas(map: map, p: p, t: t, focused: focused)
                .frame(height: Self.height * t.scale)
                .padding(.horizontal, matte ? -6 : -11)
            if MapFoot.says(map) { MapFoot(map: map, p: p, t: t).padding(.top, 7) }
        }
        .id("map")
    }
}

/// What the map can't place, counted with their marks, trouble first; and
/// where its places come from when `topo` sends no map.
struct MapFoot: View {
    var map: MapSection
    var p: CardsPalette
    var t: CardsType

    /// Whether there's anything to say beneath the map.
    nonisolated static func says(_ m: MapSection) -> Bool {
        m.isTooLarge || m.source == .places || !m.isCurrent || !m.unplaced.isEmpty
    }

    var body: some View {
        let unplaced = Mark.troubleFirst(map.unplaced, by: \.mark)
        HStack(spacing: 6) {
            if map.isTooLarge {
                Text(tr("Too large to draw: see the topology in Topophany"))
            } else if !unplaced.isEmpty {
                Text(tr("\(unplaced.count) without a location"))
                HStack(spacing: 2.5) {
                    ForEach(Array(unplaced.prefix(8).enumerated()), id: \.offset) { _, n in
                        CardMark(mark: n.mark, size: 8, color: p.listColor(n.mark))
                    }
                    if unplaced.count > 8 { Text("+\(unplaced.count - 8)").padding(.leading, 2) }
                }
            }
            Spacer(minLength: 4)
            if map.source == .places {
                Text(tr("placed by name"))
            } else if !map.isCurrent {
                Text(tr("not current"))
            }
        }
        .font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The map itself. In the panel it moves: scroll or pinch to zoom, drag
/// to move it, click to select it for the keyboard, double-click to go back
/// to its framing. Elsewhere it's drawn still, framed.
struct MapCanvas: View {
    var map: MapSection
    var p: CardsPalette
    var t: CardsType
    var detail = MapDetail.places
    var vibrant = false
    var focused = false
    @Environment(\.mapViewport) private var viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragged: CGSize = .zero
    @State private var pinch = 1.0

    var body: some View {
        let transform = viewport?.transform ?? .identity
        let painter = CardsMapPainter(map: map, p: p, t: t, detail: detail, vibrant: vibrant)
        let canvas = MapLayer(painter: painter, transform: transform, asynchronous: viewport != nil)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MapWords.summary(map))
        if let viewport {
            canvas
                .overlay { selection(viewport) }
                .overlay(alignment: .bottomTrailing) { zoomChip(viewport) }
                .contentShape(Rectangle())
                .gesture(drag(viewport))
                .simultaneousGesture(magnify(viewport))
                .onTapGesture(count: 2) { viewport.reset(easing: MapViewport.easing(reduceMotion: reduceMotion)) }
                .onTapGesture { viewport.isSelected = true }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport.frame = $0 }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport.layout($0) }
                .onChange(of: map.frame) { viewport.reset() }
                .accessibilityAction(named: tr("Zoom In")) { viewport.step(in: true) }
                .accessibilityAction(named: tr("Zoom Out")) { viewport.step(in: false) }
                .accessibilityAction(named: tr("Show Every Place")) { viewport.reset() }
        } else {
            canvas
        }
    }

    func drag(_ v: MapViewport) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                v.pan(by: CGSize(width: g.translation.width - dragged.width, height: g.translation.height - dragged.height))
                dragged = g.translation
            }
            .onEnded { _ in dragged = .zero }
    }

    func magnify(_ v: MapViewport) -> some Gesture {
        MagnifyGesture()
            .onChanged { g in
                v.zoom(by: g.magnification / pinch, at: g.startLocation)
                pinch = g.magnification
            }
            .onEnded { _ in pinch = 1 }
    }

    /// Focused by the keyboard, a faint ring; selected, the accent's. The
    /// card's title says what the keys do.
    @ViewBuilder func selection(_ v: MapViewport) -> some View {
        let on = v.isSelected || focused
        Rectangle()
            .strokeBorder(p.accent.opacity(v.isSelected ? 0.85 : 0.4), lineWidth: v.isSelected ? 1.25 : 1)
            .opacity(on ? 1 : 0)
            .animation(Highlight.easing(on), value: on)
            .allowsHitTesting(false)
    }

    /// While magnified: how far, and a way back to the framing.
    @ViewBuilder func zoomChip(_ v: MapViewport) -> some View {
        if v.isZoomed {
            Button { v.reset(easing: MapViewport.easing(reduceMotion: reduceMotion)) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 8, weight: .semibold))
                    Text(Self.zoomText(v.zoom)).font(t.mono(9.5, .medium))
                }
                .foregroundStyle(p.l2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(p.fill2))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .help(map.frame == .world ? tr("Back to the whole world") : tr("Back to every place"))
            .padding(6)
            .transition(.opacity)
        }
    }

    nonisolated static func zoomText(_ z: Double) -> String {
        z < 9.95 ? String(format: "%.1f×", z) : String(format: "%.0f×", z)
    }
}

/// The map's drawing, its transform animatable: a keyboard step or a way
/// back to the framing eases there, a drag or a scroll follows at once.
struct MapLayer: View, @MainActor Animatable {
    var painter: CardsMapPainter
    var transform: MapTransform
    var asynchronous = false

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(transform.zoom, AnimatablePair(transform.offset.x, transform.offset.y)) }
        set { transform = MapTransform(zoom: newValue.first, offset: CGPoint(x: newValue.second.first, y: newValue.second.second)) }
    }

    var body: some View {
        Canvas(rendersAsynchronously: asynchronous) { ctx, size in painter.draw(ctx, size: size, transform: transform) }
    }
}

/// What VoiceOver reads for a map.
public enum MapWords {
    public static func summary(_ m: MapSection) -> String {
        let places = m.places
        var parts = [tr("Map"), tr("\(places.count) places")]
        let trouble = m.placed.filter { !$0.isColo && ($0.mark == .down || $0.mark == .degraded) }
        for n in trouble.prefix(5) {
            parts.append(Words.join([n.name, n.place, n.mark.word]))
        }
        if !m.unplaced.isEmpty { parts.append(tr("\(m.unplaced.count) without a location")) }
        return parts.joined(separator: ", ")
    }
}

/// The Map widget: the map across the whole widget under its heading, as
/// much said beside each place as the size has room for, and beneath it
/// what the map can't place and how old it is.
struct WidgetMap: View {
    var model: WidgetModel
    var size: WidgetSize
    var p: CardsPalette
    var t: CardsType
    var ctx: RenderContext

    var detail: MapDetail {
        switch size {
        case .small: .marks
        case .medium: .places
        case .large, .extraLarge: .nodes
        }
    }

    var body: some View {
        let vibrant = ctx.widgetRendering == .vibrant
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let m = model.map {
                    WidgetHeading(symbol: "map", title: tr("Map"), meta: size == .small ? "" : meta(m), p: p, t: t)
                } else {
                    WidgetHeading(symbol: "map", title: tr("Map"), meta: "", p: p, t: t)
                }
                WidgetMark(palette: p, rendering: ctx.widgetRendering).padding(.leading, 8)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            .padding(.horizontal, 14).padding(.top, 13)
            if let m = model.map {
                MapCanvas(map: m, p: p, t: t, detail: detail, vibrant: vibrant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                foot(m).padding(.horizontal, 14).padding(.bottom, 11).padding(.top, 2)
            } else {
                Spacer(minLength: 0)
                Text(tr("Not received yet")).font(t.font(11)).foregroundStyle(p.l3).padding(14)
            }
        }
    }

    func meta(_ m: MapSection) -> String {
        tr("\(m.places.count) places")
    }

    @ViewBuilder func foot(_ m: MapSection) -> some View {
        let unplaced = Mark.troubleFirst(m.unplaced, by: \.mark)
        HStack(spacing: 5) {
            if !unplaced.isEmpty && size != .small {
                Text(tr("\(unplaced.count) without a location")).lineLimit(1)
                HStack(spacing: 2) {
                    ForEach(Array(unplaced.prefix(6).enumerated()), id: \.offset) { _, n in
                        CardMark(mark: n.mark, size: 7.5, color: ctx.widgetRendering == .vibrant ? p.l1 : p.listColor(n.mark))
                    }
                }
            } else if m.source == .places {
                Text(tr("placed by name"))
            }
            Spacer(minLength: 4)
            if !model.isCurrent {
                Text(tr("Not current"))
            } else if let at = model.updatedAt {
                Age(date: at, now: model.status.now, live: ctx.liveDates, compact: size == .small)
            }
        }
        .font(t.font(10)).foregroundStyle(p.l3).lineLimit(1)
    }
}
