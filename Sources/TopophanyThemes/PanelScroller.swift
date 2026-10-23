import SwiftUI

/// Owns the scroll binding and its animated writebacks, apart from the
/// views that build cards and terminal scenes. Content is passed as a
/// value, so moving the viewport never constructs it again.
struct PanelScroller<Content: View>: View {
    @Bindable var state: PanelScrollState
    var height: Double
    var panelHeight: Double
    var focus: String?
    var leaps: Int
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) { content }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .scrollPosition($state.position)
                .onScrollGeometryChange(for: PanelLeap.self, of: PanelLeap.init) { _, geometry in state.update(geometry) }
                .frame(height: height)
                .onChange(of: focus) { _, focus in
                    guard let focus else { return }
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo(focus) }
                }
                .onChange(of: leaps) { state.leap(panel: panelHeight, reduceMotion: reduceMotion) }
        }
    }
}

/// Edge changes belong to the mask alone, rather than the card tree.
struct PanelScrollFade: View {
    var state: PanelScrollState
    var enabled: Bool

    var body: some View {
        ScrollEdgeFade(top: enabled && !state.atTop, bottom: enabled && !state.atEnd)
    }
}
