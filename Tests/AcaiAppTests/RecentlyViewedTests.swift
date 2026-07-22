import Foundation
import Testing
@testable import AcaiApp

/// `RecentlyViewed` (B54): recency-ordering + pin-persistence, the model half of "Recently Viewed
/// + pinning" — Layer 0, per the backlog's own verification and its "data shape, not the finished
/// UI" scope note.
@Suite("RecentlyViewed")
struct RecentlyViewedTests {

    @Test("Opening an item puts it at the front")
    func recordOpenedInsertsAtFront() {
        var recent = RecentlyViewed()
        recent.recordOpened(.codebase(UUID(0)))
        recent.recordOpened(.codebase(UUID(1)))
        #expect(recent.recents == [.codebase(UUID(1)), .codebase(UUID(0))])
    }

    @Test("Reopening an already-recent item moves it to the front instead of duplicating it")
    func recordOpenedDedupsAndMovesToFront() {
        var recent = RecentlyViewed()
        let a = RecentlyViewedItem.codebase(UUID(0))
        let b = RecentlyViewedItem.codebase(UUID(1))
        recent.recordOpened(a)
        recent.recordOpened(b)
        recent.recordOpened(a)
        #expect(recent.recents == [a, b])
    }

    @Test("Recording more than the cap drops the oldest")
    func recordOpenedTrimsToMaxRecents() {
        var recent = RecentlyViewed()
        for i in 0..<(RecentlyViewed.maxRecents + 3) {
            recent.recordOpened(.codebase(UUID(i)))
        }
        #expect(recent.recents.count == RecentlyViewed.maxRecents)
        // The three oldest (0, 1, 2) fell off; the most recent is first.
        #expect(recent.recents.first == .codebase(UUID(RecentlyViewed.maxRecents + 2)))
        #expect(!recent.recents.contains(.codebase(UUID(0))))
    }

    @Test("Toggling a pin twice returns to unpinned")
    func togglePinTwiceUnpins() {
        var recent = RecentlyViewed()
        let item = RecentlyViewedItem.codebase(UUID(0))
        recent.togglePin(item)
        #expect(recent.isPinned(item))
        recent.togglePin(item)
        #expect(!recent.isPinned(item))
    }

    @Test("A pinned item stays first in display order regardless of recency")
    func displayOrderKeepsPinnedFirst() {
        var recent = RecentlyViewed()
        let old = RecentlyViewedItem.codebase(UUID(0))
        let newer = RecentlyViewedItem.codebase(UUID(1))
        recent.recordOpened(old)
        recent.togglePin(old)
        recent.recordOpened(newer)
        #expect(recent.displayOrder == [old, newer])
    }

    @Test("A pinned item never appears twice in display order")
    func displayOrderDoesNotDuplicatePinnedItems() {
        var recent = RecentlyViewed()
        let item = RecentlyViewedItem.codebase(UUID(0))
        recent.recordOpened(item)
        recent.togglePin(item)
        #expect(recent.displayOrder == [item])
    }

    @Test("Removing an item clears it from both recents and pinned")
    func removeClearsBothLists() {
        var recent = RecentlyViewed()
        let item = RecentlyViewedItem.codebase(UUID(0))
        recent.recordOpened(item)
        recent.togglePin(item)
        recent.remove(item)
        #expect(!recent.recents.contains(item))
        #expect(!recent.isPinned(item))
        #expect(recent.displayOrder.isEmpty)
    }
}

extension UUID {
    /// A deterministic UUID from a small integer, for test fixtures that need distinct-but-stable ids.
    fileprivate init(_ value: Int) {
        self.init(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
