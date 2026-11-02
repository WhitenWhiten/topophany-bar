import SwiftUI
import TopophanySections

/// Every standalone card must identify historical readings, even without a
/// Status card. Reserve a line instead of covering the existing content.
struct SnapshotWidget<Content: View>: View {
    var model: WidgetModel
    var bounds: CGSize
    var context: RenderContext
    var ink: Color
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        Group {
            if let at = model.status.historicalAt, model.kind != .status {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(tr("Last snapshot"))
                        Spacer(minLength: 0)
                        Age(date: at, now: model.status.now, live: context.liveDates)
                    }
                    .font(.system(size: 10)).foregroundStyle(ink).lineLimit(1)
                    .padding(.horizontal, 14).frame(height: 22)
                    content(CGSize(width: bounds.width, height: max(0, bounds.height - 22)))
                }
            } else {
                content(bounds)
            }
        }
        .saturation(model.status.historicalAt == nil ? 1 : 0.35)
    }
}
