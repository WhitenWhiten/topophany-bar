import Foundation
import TopophanyKit
import TopophanySections

/// One prepared drawing per section, bounded by the panel's section count.
/// Absolute positions are part of the key: a section above changing height
/// cannot leave old text, hit regions or keyboard focus behind.
@MainActor
final class CellsPanelCache {
    struct Key: Equatable {
        var section: PanelModel.Section
        var theme: Theme
        var y: Double
        var focus: String?
        var focusFirstAttention: Bool
        var language: String
    }

    struct Entry {
        var key: Key
        var items: [CellItem]
        var end: Double
        var focus: CGRect?
        var map: CGRect?
        var mapMeta: CGRect?
    }

    private var sections: [SectionID: Entry] = [:]

    func entry(for key: Key) -> Entry? {
        guard let entry = sections[key.section.id], entry.key == key else { return nil }
        return entry
    }

    func store(_ entry: Entry) { sections[entry.key.section.id] = entry }
}
