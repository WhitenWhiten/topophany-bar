import Foundation
import TopophanySections

/// A localized string from this module's catalog, in the panel's language.
func tr(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: L10n.bundle(for: .module))
}
