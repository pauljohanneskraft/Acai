import XCTest

/// Verifies the codebase-delete confirmation dialog (`USABILITY_GUARDRAILS.md` §3: cancel/confirm
/// both actually do what they say, never just closing the sheet without acting or acting without
/// asking) against the fixture-seeded codebase, via `ProjectDetailView`'s own confirmation flow —
/// the one reachable from a codebase row on every width. Each test launches its own fresh copy of
/// the fixture (`XCUIApplication.launchWithFixture(_:)`), so a confirmed deletion in one test
/// never affects another.
final class DeleteConfirmationTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private func openSeededCodebaseRow(_ app: XCUIApplication) -> XCUIElement {
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))
        return codebaseRow
    }

    /// Reveals the row's "Delete" action and taps it, starting the confirmation flow.
    /// `.swipeActions` (compact width) is a more reliable XCUITest target than a long-press context
    /// menu — right-click's the macOS equivalent, since `.swipeActions` is iOS/iPadOS-only.
    private func tapDelete(on row: XCUIElement, app: XCUIApplication) {
        #if os(macOS)
        row.rightClick()
        app.buttons["Delete"].tap()
        #else
        row.swipeLeft()
        app.buttons["Delete"].tap()
        #endif
    }

    func testCancellingTheConfirmationKeepsTheCodebase() throws {
        let app = XCUIApplication()
        let codebaseRow = openSeededCodebaseRow(app)
        tapDelete(on: codebaseRow, app: app)

        // At this window size, `.confirmationDialog` renders as a **popover** anchored near the
        // row, not a bottom action sheet — confirmed by dumping the accessibility tree: it has no
        // "Cancel" button at all, only the destructive "Delete Codebase" action and a
        // `PopoverDismissRegion` element (tap-outside-to-dismiss is the cancel affordance for a
        // popover presentation). Tapping that region is this presentation's actual "Cancel".
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5))
        dismissRegion.tap()

        XCTAssertTrue(codebaseRow.exists, "cancelling the confirmation must not delete the codebase")
    }

    func testConfirmingTheConfirmationRemovesTheCodebase() throws {
        let app = XCUIApplication()
        let codebaseRow = openSeededCodebaseRow(app)
        tapDelete(on: codebaseRow, app: app)

        let detail = ProjectDetailScreen(app: app)
        XCTAssertTrue(detail.deleteCodebaseConfirmButton.waitForExistence(timeout: 5))
        detail.deleteCodebaseConfirmButton.tap()

        XCTAssertFalse(codebaseRow.waitForExistence(timeout: 5), "confirming the deletion must remove the codebase")
    }
}
