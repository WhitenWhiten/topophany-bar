import SwiftUI
import TopophanySections

/// A string from the app's catalog, in the language the user chose for
/// Topophany, or the system's.
func tr(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: L10n.bundle(for: .main))
}

/// A form in that language: SwiftUI looks its words up in the
/// environment's locale, so a new choice applies at once.
struct Localized<Content: View>: View {
    @Environment(AppModel.self) private var model
    var content: Content

    var body: some View {
        // Built anew for a new choice, which L10n already has: menus keep
        // their items' words otherwise.
        content.environment(\.locale, L10n.locale)
            .id(model.settings.language)
    }
}
