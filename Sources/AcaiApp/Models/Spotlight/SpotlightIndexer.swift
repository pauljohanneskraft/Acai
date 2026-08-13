@preconcurrency import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Keeps the on-device Core Spotlight index in sync with Quick Open's own entry list, resolved
/// back into the app through each entry's stable `id` (see `ProjectBrowserView+Handoff.swift`).
struct SpotlightIndexer: Sendable {
    /// Scopes every item this indexer writes so `reindex(_:)` can wipe and replace just its own
    /// items, without touching anything else Spotlight might index for this app.
    static let domainIdentifier = "de.kraftsoftware.acai.quickOpen"

    private let index: CSSearchableIndex

    init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    /// Replaces every previously indexed item with `entries`' current set. A no-op (not an error)
    /// when this device doesn't support on-device indexing.
    func reindex(_ entries: [QuickOpenEntry]) async throws {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let items = entries.map { searchableItem(for: $0) }
        try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
        try await index.indexSearchableItems(items)
    }

    /// Not `private`: exercised directly by `SpotlightIndexerTests`.
    func searchableItem(for entry: QuickOpenEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = entry.name
        attributes.contentDescription = entry.subtitle
        return CSSearchableItem(
            uniqueIdentifier: entry.id, domainIdentifier: Self.domainIdentifier, attributeSet: attributes)
    }
}
