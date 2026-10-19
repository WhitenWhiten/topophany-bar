import Foundation

/// The menu bar's alert, quieted until it gets worse. It changes how the
/// item looks, never what it says: the badge keeps its shape and the count
/// stays, both in the menu bar's own ink. The panel and the widgets show
/// everything as before.
///
/// It ends when the verdict asks for more attention than it did, as the
/// item's ripple does (a worse mark, or more under the same mark), and when
/// the verdict clears, so the next problem alerts afresh. As the verdict
/// eases, the quiet eases with it: a problem that improves and then worsens
/// again alerts again. While nothing current is known, it holds.
public struct QuietAlert: Sendable, Hashable {
    /// What it was quieted at, or has eased to since.
    public var mark: Mark
    public var count: Int?

    public init(mark: Mark, count: Int?) {
        self.mark = mark
        self.count = count
    }

    /// Quiets what `status` shows; `nil` when it shows no alert.
    public init?(_ status: StatusSection) {
        guard Self.alerts(status) else { return nil }
        self.init(mark: status.mark, count: status.count)
    }

    /// Whether `status` is an alert to quiet: a current verdict of
    /// degraded, incidents or down.
    public static func alerts(_ status: StatusSection) -> Bool {
        status.verdictState != nil && (status.mark == .degraded || status.mark == .down)
    }

    /// The quiet once `status` is shown; `nil` when it ends.
    public func after(_ status: StatusSection) -> QuietAlert? {
        if status.verdictState == .clear { return nil }
        guard Self.alerts(status) else { return self }
        if StatusItemModel.asksMoreAttention(status.mark, status.count, than: mark, count) { return nil }
        return QuietAlert(mark: status.mark, count: status.count)
    }
}

/// The menu bar's alert as the panel offers it.
public enum MenuBarAlert: Sendable, Hashable {
    /// Nothing to quiet: no alert, or the item draws no status colors.
    case unavailable
    /// In color in the menu bar; it can be quieted.
    case shown
    /// Quieted until it gets worse; it can be shown again.
    case quiet
}
