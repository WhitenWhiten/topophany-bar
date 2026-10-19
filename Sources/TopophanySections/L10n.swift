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

    /// A localization for one task and what it calls, ahead of the forced
    /// one: tests in other languages run beside tests in English.
    @TaskLocal public static var scoped: String?

    public static func with<T>(_ localization: String, _ body: () throws -> T) rethrows -> T {
        try $scoped.withValue(localization, operation: body)
    }

    private static var chosen: String? { scoped ?? forced.withLock { $0 } }

    public static var localization: String {
        chosen ?? Bundle.module.preferredLocalizations.first ?? "en"
    }

    /// The locale clock times are written in: the panel's language, with
    /// this Mac's region and its 12- or 24-hour choice. A forced
    /// localization takes its language's own, so snapshots don't depend on
    /// the Mac that draws them.
    public static var locale: Locale {
        let base = Locale(identifier: localization)
        guard chosen == nil else { return base }
        var c = Locale.Components(locale: base)
        c.region = Locale.current.region
        c.hourCycle = Locale.current.hourCycle
        return Locale(components: c)
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
        guard let l = chosen,
              let path = base.path(forResource: l, ofType: "lproj"),
              let b = Bundle(path: path) else { return base }
        return b
    }
}

/// A localized string from this module's catalog.
func tr(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: L10n.bundle)
}
