import SwiftUI
import TopophanySections

struct CardsWidget: View {
    var model: WidgetModel
    var size: WidgetSize
    var ctx: RenderContext

    var body: some View {
        Text(model.status.title).frame(width: size.width, height: size.height)
    }
}
