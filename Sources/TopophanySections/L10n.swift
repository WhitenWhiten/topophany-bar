import Foundation
import Synchronization

/// Where the panel's words come from. They follow the system's languages
/// unless a localization is forced, as snapshot tests do.
public enum L10n {
    private static let forced = Mutex<String?>(nil)

    /// Forces a localization (`en`, `ja` or `zh-Hans`), or `nil` to follow
    /// the system.
    public static func force(_ localization: String?) {
        forced.withLock { $0 = localization }
    }

    public static var localization: String {
        forced.withLock { $0 } ?? Bundle.module.preferredLocalizations.first ?? "en"
    }

    /// The language to ask `topo preview` for: `en`, `ja` or `zh`.
    public static var previewLanguage: String {
        let l = localization
        if l.hasPrefix("ja") { return "ja" }
        if l.hasPrefix("zh") { return "zh" }
        return "en"
    }

    static var bundle: Bundle { bundle(for: .module) }

    /// `base`, or its forced localization's sub-bundle.
    public static func bundle(for base: Bundle) -> Bundle {
        guard let l = forced.withLock({ $0 }),
              let path = base.path(forResource: l, ofType: "lproj"),
              let b = Bundle(path: path) else { return base }
        return b
    }
}

/// A localized string from this module's catalog.
func tr(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: L10n.bundle)
}
