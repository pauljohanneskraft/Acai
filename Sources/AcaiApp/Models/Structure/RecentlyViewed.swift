import Foundation

/// Tracked across every project so "Recently Viewed" isn't scoped to just one, matching
/// `ProjectBrowserViewModel.Selection`'s shape.
enum RecentlyViewedItem: Codable, Hashable, Sendable {
    case generatedDiagram(UUID)
    case freeformDiagram(UUID)
    case codebase(UUID)
}

/// Tracks the last ~10 things opened across every project, most-recent-first, plus per-item
/// pinning that keeps a favorite listed regardless of recency.
///
/// Model-only: nothing in the app calls `recordOpened(_:)` yet — that's wiring into
/// `ProjectBrowserViewModel`'s navigation, deferred alongside the "Recently Viewed" sidebar UI and
/// Quick Open itself.
struct RecentlyViewed: Codable, Hashable, Sendable {
    private(set) var recents: [RecentlyViewedItem] = []
    private(set) var pinned: [RecentlyViewedItem] = []

    static let maxRecents = 10

    init() {}

    /// A pinned item is still recorded here (so it keeps an accurate recency position if ever
    /// unpinned) — `displayOrder` is what actually keeps it listed regardless of recency, not an
    /// exemption from trimming.
    mutating func recordOpened(_ item: RecentlyViewedItem) {
        recents.removeAll { $0 == item }
        recents.insert(item, at: 0)
        if recents.count > Self.maxRecents {
            recents.removeLast(recents.count - Self.maxRecents)
        }
    }

    func isPinned(_ item: RecentlyViewedItem) -> Bool {
        pinned.contains(item)
    }

    mutating func togglePin(_ item: RecentlyViewedItem) {
        if let index = pinned.firstIndex(of: item) {
            pinned.remove(at: index)
        } else {
            pinned.insert(item, at: 0)
        }
    }

    var displayOrder: [RecentlyViewedItem] {
        pinned + recents.filter { !pinned.contains($0) }
    }

    /// Call when the underlying diagram/codebase itself is deleted, so a stale reference never
    /// lingers.
    mutating func remove(_ item: RecentlyViewedItem) {
        recents.removeAll { $0 == item }
        pinned.removeAll { $0 == item }
    }
}
