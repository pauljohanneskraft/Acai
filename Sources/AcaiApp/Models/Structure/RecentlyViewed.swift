import Foundation

/// One thing the user can open directly from the sidebar/Quick Open — a generated diagram, a
/// freeform diagram, or a codebase's detail screen — tracked across every project so "Recently
/// Viewed" isn't scoped to just one, matching `ProjectBrowserViewModel.Selection`'s shape.
enum RecentlyViewedItem: Codable, Hashable, Sendable {
    case generatedDiagram(UUID)
    case freeformDiagram(UUID)
    case codebase(UUID)
}

/// Tracks the last ~10 things opened across every project, most-recent-first, plus per-item
/// pinning that keeps a favorite listed regardless of recency. See `USABILITY_IMPROVEMENTS.md`
/// Part 8, "Recently viewed and pinned."
///
/// Model-only: nothing in the app calls `recordOpened(_:)` yet (that's wiring into
/// `ProjectBrowserViewModel`'s navigation, deferred alongside the actual "Recently Viewed" sidebar
/// UI and Quick Open itself, B35) — this stays inert (both lists start and remain empty) until
/// that lands, exactly the "data shape, not the finished UI" scope B54 calls for.
struct RecentlyViewed: Codable, Hashable, Sendable {
    private(set) var recents: [RecentlyViewedItem] = []
    private(set) var pinned: [RecentlyViewedItem] = []

    static let maxRecents = 10

    init() {}

    /// Records `item` as just opened: moves it to the front if already present, inserts it
    /// otherwise, then trims to `maxRecents`. A pinned item is still recorded here (so it keeps an
    /// accurate recency position if ever unpinned) — `displayOrder` is what actually keeps it
    /// listed regardless of recency, not an exemption from trimming.
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

    /// Pins `item` if it isn't already pinned (most-recently-pinned first), or unpins it if it is —
    /// the single context-menu action, mirroring how rename/delete are each one action.
    mutating func togglePin(_ item: RecentlyViewedItem) {
        if let index = pinned.firstIndex(of: item) {
            pinned.remove(at: index)
        } else {
            pinned.insert(item, at: 0)
        }
    }

    /// The list to actually display: every pinned item first (most-recently-pinned first), then
    /// unpinned recents in recency order — a pinned item never appears twice even though it can be
    /// in both `pinned` and `recents` at once internally.
    var displayOrder: [RecentlyViewedItem] {
        pinned + recents.filter { !pinned.contains($0) }
    }

    /// Removes every trace of `item` from both lists — call when the underlying diagram/codebase
    /// itself is deleted, so a stale reference never lingers and resolves to nothing.
    mutating func remove(_ item: RecentlyViewedItem) {
        recents.removeAll { $0 == item }
        pinned.removeAll { $0 == item }
    }
}
