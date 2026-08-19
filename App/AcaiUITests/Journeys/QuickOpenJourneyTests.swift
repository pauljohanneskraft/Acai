import XCTest

/// Selection-routing logic is covered by `QuickOpenControllerTests`; this only proves the sheet
/// opens, search filters, and tapping a result actually navigates.
///
/// Searches for the seeded freeform diagram rather than the codebase itself: `QuickOpenView`
/// deliberately drops `.project`/`.codebase` entries from the searchable list (they exist on
/// `QuickOpenIndexBuilder`'s output only so `SpotlightIndexer` can consume them), so a codebase name
/// is a query Quick Open can never answer. Type entries would need a reindex first, since
/// `QuickOpenIndexBuilder` reads `store.artifacts` rather than the injected fixture artifact.
@MainActor
final class QuickOpenJourneyTests: UIJourneyTestCase {
    private static let freeformDiagramID = "33333333-3333-3333-3333-333333333333"

    func testSearchingAndSelectingADiagramNavigatesToIt() throws {
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded")

        ProjectBrowserScreen(app: app).openQuickOpen()

        let quickOpen = QuickOpenScreen(app: app)
        XCTAssertTrue(quickOpen.searchField.waitForExistence(timeout: 10))
        // Search filters `allEntries` reactively only on query changes, not once the index finishes
        // building — typing before `buildIndex()` completes would filter against an empty list and
        // never re-run, permanently showing zero results.
        XCTAssertTrue(quickOpen.loadingState.waitForNonExistence(timeout: 10))

        let result = quickOpen.result(id: "freeformDiagram:\(Self.freeformDiagramID)")
        XCTAssertTrue(
            quickOpen.search("Seeded Freeform Diagram", until: result),
            "searching for the seeded freeform diagram should surface its result row"
        )
        result.tap()

        // Undo/Redo rather than a freeform-specific control: they survive iPhone's toolbar
        // collapse, while `checkpointsButton` is only directly reachable at regular width.
        let diagram = FreeformDiagramScreen(app: app)
        XCTAssertTrue(diagram.undoButton.waitForExistence(timeout: 10),
                      "selecting the diagram result should have navigated to the diagram")
        XCTAssertTrue(quickOpen.searchField.waitForNonExistence(timeout: 5),
                      "navigating should have dismissed the Quick Open sheet")
    }
}
