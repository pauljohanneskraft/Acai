import XCTest

/// B53: a destructive "Delete Project…"/"Delete Codebase…" button at the bottom of
/// `ProjectDetailView`/`CodebaseDetailView` — a second, discoverable path to the same
/// confirmed-safe action `DeleteConfirmationTests` already covers via the sidebar/row context
/// menu. Each test launches its own fresh copy of the fixture, so a confirmed deletion in one
/// test never affects another.
final class DiscoverableDeletePathTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testDeleteCodebaseButtonOnItsOwnDetailScreenRemovesIt() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))
        codebaseRow.tap()

        let codebaseDetail = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebaseDetail.deleteCodebaseButton.waitForExistence(timeout: 10))
        codebaseDetail.deleteCodebaseButton.tap()

        XCTAssertTrue(codebaseDetail.deleteCodebaseConfirmButton.waitForExistence(timeout: 5))
        codebaseDetail.deleteCodebaseConfirmButton.tap()

        XCTAssertFalse(
            codebaseRow.waitForExistence(timeout: 5),
            "confirming the codebase's own delete button must remove it, same as the row's context menu"
        )
    }

    func testDeleteProjectButtonOnItsOwnDetailScreenRemovesIt() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        XCTAssertTrue(detail.deleteProjectButton.waitForExistence(timeout: 10))
        detail.deleteProjectButton.tap()

        XCTAssertTrue(detail.deleteProjectConfirmButton.waitForExistence(timeout: 5))
        detail.deleteProjectConfirmButton.tap()

        XCTAssertFalse(
            projectRow.waitForExistence(timeout: 5),
            "confirming the project's own delete button must remove it, same as the sidebar's context menu"
        )
    }
}
