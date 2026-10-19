import SwiftUI

/// Where the panel's scroll stands, for the quick scroll in its footer.
/// Each leap goes down about half the panel, never further than the
/// scroll shows at once, so no row passes unseen; from the end, it goes
/// back to the top.
struct PanelLeap: Equatable {
    var offset = 0.0
    var content = 0.0
    var visible = 0.0

    init(offset: Double = 0, content: Double = 0, visible: Double = 0) {
        self.offset = offset
        self.content = content
        self.visible = visible
    }

    init(_ g: ScrollGeometry) {
        self.init(offset: g.contentOffset.y, content: g.contentSize.height, visible: g.containerSize.height)
    }

    /// Nothing further down: the next leap goes back up.
    var atEnd: Bool { offset >= content - visible - 1 }

    /// Nothing further up.
    var atTop: Bool { offset <= 1 }

    /// Where the next leap lands, as the scroll's offset from the top, in a
    /// panel `panel` points tall.
    func target(panel: Double) -> Double {
        atEnd ? 0 : min(offset + min(panel / 2, visible), content - visible)
    }
}
