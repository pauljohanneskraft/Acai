import XCTest

/// `QueryView`, scoped to the seeded fixture's `SampleSwiftPackage` codebase: `Base` is the only
/// type with a publicly-settable stored property (`id`) among the fixture's four classes
/// (`Base`, `Derived`, `Helper`, `Worker`) — `Derived.helper`/`Helper.worker` are `private`, and
/// `Worker` has no stored properties at all — so toggling "Mutable public state only" is a real,
/// known-answer filter, not just a smoke check that the screen opens.
@MainActor
final class QueryJourneyTests: UIJourneyTestCase {

    func testQueryViewFiltersByMutablePublicState() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .parsed)

        let query = QueryScreen(app: app)
        codebaseDetail.queryButton.tap("Query", until: query.list)
        query.row(id: "Base").waitOrFail("the Base query row")
        XCTAssertTrue(query.row(id: "Worker").exists)

        // Every filter control lives in a sheet, not inline above the results.
        query.filterButton.tap("the query filter button", until: query.mutablePublicStateToggle)
        query.mutablePublicStateToggle.tapWhenReady("Mutable public state only")
        query.filterSheetDoneButton.tapWhenReady("the filter sheet's Done button")

        query.row(id: "Worker").waitForDisappearanceOrFail(
            "the Worker query row (it has no stored properties and shouldn't match \"mutable public state only\")"
        )
        query.row(id: "Base").waitOrFail("the Base query row (its public settable `id` should still match)")
        XCTAssertFalse(
            query.row(id: "Derived").exists,
            "Derived's only property (`helper`) is private and shouldn't match.")

        query.filterButton.tap("the query filter button", until: query.clearFiltersButton)
        query.clearFiltersButton.tapWhenReady("Clear Filters")
        query.filterSheetDoneButton.tapWhenReady("the filter sheet's Done button")

        query.row(id: "Worker").waitOrFail("the Worker query row after clearing filters")

        validateScreenshot("Query", state: "listPopulated")
    }
}
