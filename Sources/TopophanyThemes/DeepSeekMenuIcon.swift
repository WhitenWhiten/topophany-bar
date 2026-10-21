import SwiftUI
import TopophanySections

extension StatusItemModel {
    public func portrait(in context: StatusItemContext) -> MenuBarIconAnimation? {
        switch icon {
        case .globe: nil
        case .deepseek: MenuBarIconAnimation.deepseek
        case .whiteNight: MenuBarIconAnimation.whiteNight
        case .custom: context.customIcon
        }
    }
}

/// Settings and snapshot rendering; the app plays these same frames on a
/// separate Core Animation layer without repeatedly redrawing the status.
struct MenuBarPortrait: View {
    var animation: MenuBarIconAnimation
    var height: Double
    var speed: Double
    var motion: StatusItemMotion

    var body: some View {
        let time = motion.moves ? motion.time * speed : 0
        let phase = animation.id == "deepseek" && motion.moves ? sin(time * 2 * .pi / 4.8) : 0
        let size = animation.size(height: height)
        Image(decorative: animation.frame(at: time), scale: 2)
            .renderingMode(.original).resizable().interpolation(animation.id == "whiteNight" ? .none : .high).scaledToFit()
            .frame(width: size.width - 2, height: size.height - 2)
            .offset(y: phase * 0.25)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}

struct DeepSeekMenuIcon: View {
    var motion: StatusItemMotion
    var body: some View {
        if let animation = MenuBarIconAnimation.deepseek {
            MenuBarPortrait(animation: animation, height: 26, speed: 1, motion: motion)
        }
    }
}
