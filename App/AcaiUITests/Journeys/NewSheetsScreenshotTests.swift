import XCTest

/// Golden screenshots for the two "New ..." sheets not covered by any existing journey:
/// `NewProjectSheet`'s empty form, and `NewCodebaseSheet`'s local-folder tab (the default tab,
/// distinct from the GitHub tab already exercised by `GitHubSignInTests`/`GitHubAddCodebaseTests`).
/// The local tab's "Choose…" button opens a real system file picker (`NSOpenPanel`/document
/// picker), which XCUITest can't drive without further plumbing — this only captures the tab's
/// empty state, not a "directory chosen" state. See `TESTING_ARCHITECTURE.md` Layer 2.
final class NewSheetsScreenshotTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"

    private var comparator: ScreenshotComparator {
        ScreenshotComparator(goldenDirectory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__"))
    }

    func testNewProjectSheetScreenshot() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        XCTAssertTrue(browser.newProjectButton.waitForExistence(timeout: 10))
        browser.newProjectButton.tap()

        let sheet = NewProjectSheetScreen(app: app)
        XCTAssertTrue(sheet.titleField.waitForExistence(timeout: 10))
        comparator.validate(
            viewType: "NewProjectSheet", state: "empty",
            screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )
    }

    func testNewCodebaseSheetLocalTabScreenshot() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        XCTAssertTrue(detail.addCodebaseButton.waitForExistence(timeout: 10))
        detail.addCodebaseButton.tap()

        // `.localFolder` is the sheet's default tab — no source-picker interaction needed.
        let sheet = NewCodebaseSheetScreen(app: app)
        XCTAssertTrue(sheet.localNameField.waitForExistence(timeout: 10))
        comparator.validate(
            viewType: "NewCodebaseSheet", state: "localTabEmpty",
            screenshot: app.windows.firstMatch.screenshot(), testCase: self
        )
    }
}
