import SwiftUI

/// Form rows that reorder by dragging their label: the row lifts and
/// follows the pointer, the others make room, and on release it settles
/// into its slot. They sit in one form row, since a grouped form's own rows
/// can't be dragged. VoiceOver gets Move Up and Move Down.
struct ReorderableRows<ID: Hashable, Label: View, Trailing: View>: View {
    var ids: [ID]
    var move: ([ID]) -> Void
    @ViewBuilder var label: (ID) -> Label
    @ViewBuilder var trailing: (ID) -> Trailing

    private struct Drag {
        var id: ID
        var order: [ID]
        var startTop: Double
        var top: Double
        var settling = false
    }

    @State private var drag: Drag?
    @State private var heights: [ID: Double] = [:]
    private let space = "reorderable-rows"

    var body: some View {
        let order = drag?.order ?? ids
        VStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.element) { i, id in
                let gap = drag?.id == id
                row(id)
                    .opacity(gap ? 0 : 1)
                    .overlay(alignment: .top) {
                        if i > 0, !gap, drag?.id != order[i - 1] { Divider() }
                    }
                    .accessibilityHidden(gap)
                    .accessibilityAction(named: Text("Move Up")) { step(id, by: -1) }
                    .accessibilityAction(named: Text("Move Down")) { step(id, by: 1) }
            }
        }
        .coordinateSpace(.named(space))
        // Each row has a form row's vertical inset, so the one row they
        // share gives its own back.
        .padding(.top, -11).padding(.bottom, -10)
        .overlay(alignment: .top) {
            if let d = drag {
                row(d.id)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.2), radius: 9, y: 3)
                            .padding(.horizontal, -8)
                    }
                    .offset(y: d.top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func row(_ id: ID) -> some View {
        LabeledContent {
            trailing(id)
        } label: {
            label(id)
                .contentShape(Rectangle())
                .pointerStyle(drag == nil ? .grabIdle : .grabActive)
                .gesture(gesture(id))
        }
        .padding(.top, 11).padding(.bottom, 10)
        .onGeometryChange(for: Double.self) { $0.size.height } action: { heights[id] = $0 }
    }

    private func gesture(_ id: ID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
            .onChanged { value in
                if drag == nil, let i = ids.firstIndex(of: id) {
                    let top = tops(ids)[i]
                    drag = Drag(id: id, order: ids, startTop: top, top: top)
                }
                guard let d = drag, !d.settling else { return }
                let height = heights[d.id] ?? 0
                let total = ids.reduce(0) { $0 + (heights[$1] ?? 0) }
                let top = min(max(d.startTop + value.translation.height, 0), max(0, total - height))
                drag?.top = top
                let order = slot(d.id, top: top, in: d.order)
                if order != d.order { withAnimation(.snappy(duration: 0.22)) { drag?.order = order } }
            }
            .onEnded { _ in settle() }
    }

    private func settle() {
        guard let d = drag, let i = d.order.firstIndex(of: d.id) else { return }
        drag?.settling = true
        withAnimation(.snappy(duration: 0.2)) {
            drag?.top = tops(d.order)[i]
        } completion: {
            if d.order != ids { move(d.order) }
            drag = nil
        }
    }

    /// Each row's top, stacked in this order.
    private func tops(_ order: [ID]) -> [Double] {
        var y = 0.0
        return order.map { id in
            defer { y += heights[id] ?? 0 }
            return y
        }
    }

    /// The order with the dragged row in the slot nearest its top.
    private func slot(_ id: ID, top: Double, in order: [ID]) -> [ID] {
        let others = order.filter { $0 != id }
        var best = 0, bestDistance = Double.infinity, y = 0.0
        for k in 0...others.count {
            if abs(y - top) < bestDistance { (best, bestDistance) = (k, abs(y - top)) }
            if k < others.count { y += heights[others[k]] ?? 0 }
        }
        var out = others
        out.insert(id, at: best)
        return out
    }

    private func step(_ id: ID, by delta: Int) {
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + delta) else { return }
        var order = ids
        order.swapAt(i, i + delta)
        withAnimation(.snappy(duration: 0.22)) { move(order) }
    }
}
