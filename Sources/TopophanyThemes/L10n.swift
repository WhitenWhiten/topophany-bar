import Foundation
import TopophanySections

/// A localized string from this module's catalog, in the panel's language.
func tr(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: L10n.bundle(for: .module))
}

extension Words {
    /// "As of 5:00 AM": when a snapshot was read, in this Mac's time.
    static func asOf(_ date: Date) -> String {
        let t = Words.time(date, in: .current)
        return tr("As of \(Words.clock(t.time, t.period))")
    }
}
