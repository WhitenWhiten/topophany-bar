import SwiftUI
import TopophanySections

extension StatusItemModel {
    /// The icon in place of the globe: as the app plays it, or else drawn
    /// twice over, as SwiftUI draws it.
    public func portrait(in context: StatusItemContext) -> MenuBarIconAnimation? {
        if icon != .globe, let played = context.portrait { return played }
        return switch icon {
        case .globe: nil
        case .deepseek: MenuBarIconAnimation.deepseek
        case .whiteNight: MenuBarIconAnimation.whiteNight(pixelHeight: (iconSize - 2) * 2)
        case .custom: context.customIcon
        }
    }

    /// What that icon shows for the item's status.
    public func scene(in context: StatusItemContext) -> MenuBarIconScene? {
        portrait(in: context)?.scene(mark, tinted: tinted)
    }
}

/// Settings and snapshot rendering; the app plays these same frames on a
/// separate Core Animation layer without repeatedly redrawing the status.
struct MenuBarPortrait: View {
    var scene: MenuBarIconScene
    var height: Double
    var speed: Double
    var motion: StatusItemMotion

    var body: some View {
        let animation = scene.animation
        let time = motion.moves ? motion.time * speed : 0
        let phase = animation.id == "deepseek" && motion.moves ? sin(time * 2 * .pi / 4.8) : 0
        let size = animation.size(height: height)
        let crisp = animation.id == "whiteNight"
        ZStack {
            picture(animation.frame(at: time), crisp: crisp)
            if let overlay = scene.overlay { picture(overlay, crisp: crisp) }
        }
        .grayscale(scene.grayscale ? 1 : 0)
        .frame(width: size.width - 2, height: size.height - 2)
        .offset(y: phase * 0.25)
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    func picture(_ image: CGImage, crisp: Bool) -> some View {
        Image(decorative: image, scale: 2)
            .renderingMode(.original).resizable().interpolation(crisp ? .none : .high).scaledToFit()
    }
}

struct DeepSeekMenuIcon: View {
    var motion: StatusItemMotion
    var body: some View {
        if let animation = MenuBarIconAnimation.deepseek {
            MenuBarPortrait(scene: MenuBarIconScene(animation: animation), height: 26, speed: 1, motion: motion)
        }
    }
}
