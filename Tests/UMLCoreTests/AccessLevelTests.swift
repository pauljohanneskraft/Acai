import Testing
@testable import UMLCore

@Suite("AccessLevel")
struct AccessLevelTests {

    /// Pins the single total visibility order shared by CLI, app, and renderers so a future edit
    /// can't silently reshuffle the contested middle tiers (packagePrivate / internal / protected).
    @Test func visibilityRankIsStrictlyDescending() {
        let mostToLeastVisible: [AccessLevel] = [
            .open, .public, .packagePrivate, .internal, .protected, .filePrivate, .private
        ]
        let ranks = mostToLeastVisible.map(\.visibilityRank)
        for (higher, lower) in zip(ranks, ranks.dropFirst()) {
            #expect(higher > lower)
        }
    }

    /// The contested chain specifically: the only cross-language constraints are Swift's
    /// `packagePrivate > internal` and Kotlin's `internal > protected`, which compose into one order
    /// that contradicts no supported language (see `visibilityRank`).
    @Test func middleTierOrdering() {
        #expect(AccessLevel.packagePrivate.visibilityRank > AccessLevel.internal.visibilityRank)
        #expect(AccessLevel.internal.visibilityRank > AccessLevel.protected.visibilityRank)
    }
}
