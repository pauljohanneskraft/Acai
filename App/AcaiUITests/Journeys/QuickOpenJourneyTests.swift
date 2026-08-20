import XCTest

/// Selection-routing logic is covered by `QuickOpenControllerTests`; this only proves the sheet
/// opens, search filters, and tapping a result actually navigates.
@MainActor
final class QuickOpenJourneyTests: UIJourneyTestCase {
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testSearchingAndSelectingACodebaseNavigatesToIt() throws {
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded")

        ProjectBrowserScreen(app: app).openQuickOpen()

        let quickOpen = QuickOpenScreen(app: app)
        XCTAssertTrue(quickOpen.searchField.waitForExistence(timeout: 10))
        // Search filters `allEntries` reactively only on query changes, not once the index finishes
        // building — typing before `buildIndex()` completes would filter against an empty list and
        // never re-run, permanently showing zero results.
        XCTAssertTrue(quickOpen.loadingState.waitForNonExistence(timeout: 10))

        let result = quickOpen.result(id: "codebase:\(Self.codebaseID)")
        XCTAssertTrue(
            quickOpen.search("SampleSwiftPackage", until: result),
            "searching for the seeded codebase should surface its result row"
        )

        result.tap()

        let codebaseDetail = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10),
                      "selecting the codebase result should have navigated to its detail screen")
    }
}
