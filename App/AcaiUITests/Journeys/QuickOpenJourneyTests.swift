import XCTest

/// Selection-routing logic is covered by `QuickOpenControllerTests`; this only proves the sheet
/// opens, search filters, and tapping a result actually navigates.
@MainActor
final class QuickOpenJourneyTests: XCTestCase {
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testSearchingAndSelectingACodebaseNavigatesToIt() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        XCTAssertTrue(browser.quickOpenButton.waitForExistence(timeout: 10))
        browser.quickOpenButton.tap()

        let quickOpen = QuickOpenScreen(app: app)
        XCTAssertTrue(quickOpen.searchField.waitForExistence(timeout: 10))
        // Search filters `allEntries` reactively only on query changes, not once the index finishes
        // building — typing before `buildIndex()` completes would filter against an empty list and
        // never re-run, permanently showing zero results.
        XCTAssertTrue(quickOpen.loadingState.waitForNonExistence(timeout: 10))
        quickOpen.search("SampleSwiftPackage")

        let result = quickOpen.result(id: "codebase:\(Self.codebaseID)")
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()

        let codebaseDetail = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10),
                      "selecting the codebase result should have navigated to its detail screen")
    }
}
