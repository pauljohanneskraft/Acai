import XCTest

/// `InspectView`, scoped to the seeded fixture's `SampleSwiftPackage` codebase: `Base` is the only
/// type with a publicly-settable stored property (`id`) among the fixture's four classes
/// (`Base`, `Derived`, `Helper`, `Worker`) — `Derived.helper`/`Helper.worker` are `private`, and
/// `Worker` has no stored properties at all — so toggling "Mutable public state only" is a real,
/// known-answer filter, not just a smoke check that the screen opens.
@MainActor
final class InspectJourneyTests: UIJourneyTestCase {

    func testInspectViewFiltersByMutablePublicState() throws {
        let codebaseDetail = openPreindexedSeededCodebase()

        let inspect = InspectScreen(app: app)
        codebaseDetail.inspectButton.tap("Inspect", until: inspect.list)
        inspect.row(id: "SampleSwiftPackage.Base").waitOrFail("the Base inspect row")
        XCTAssertTrue(inspect.row(id: "SampleSwiftPackage.Worker").exists)

        // Every filter control lives in a sheet, not inline above the results.
        inspect.filterButton.tap("the inspect filter button", until: inspect.mutablePublicStateToggle)
        inspect.mutablePublicStateToggle.tapWhenReady("Mutable public state only")
        inspect.filterSheetDoneButton.tapWhenReady("the filter sheet's Done button")

        inspect.row(id: "SampleSwiftPackage.Worker").waitForDisappearanceOrFail(
            "the Worker inspect row (it has no stored properties and shouldn't match \"mutable public state only\")"
        )
        inspect.row(id: "SampleSwiftPackage.Base")
            .waitOrFail("the Base inspect row (its public settable `id` should still match)")
        XCTAssertFalse(
            inspect.row(id: "SampleSwiftPackage.Derived").exists,
            "Derived's only property (`helper`) is private and shouldn't match.")

        inspect.filterButton.tap("the inspect filter button", until: inspect.clearFiltersButton)
        inspect.clearFiltersButton.tapWhenReady("Clear Filters")
        inspect.filterSheetDoneButton.tapWhenReady("the filter sheet's Done button")

        inspect.row(id: "SampleSwiftPackage.Worker").waitOrFail("the Worker inspect row after clearing filters")

        validateScreenshot("Inspect", state: "listPopulated")
    }
}
