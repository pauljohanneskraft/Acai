import XCTest
#if os(iOS)
import UIKit
#endif

/// Verifies the codebase-delete confirmation dialog: cancel/confirm both actually do what they say,
/// never just closing the sheet without acting or acting without asking. Each test launches its own
/// fresh copy of the fixture, so a confirmed deletion in one test never affects another.
@MainActor
final class DeleteConfirmationTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    private func openSeededCodebaseRow(_ app: XCUIApplication) -> XCUIElement {
        app.rotateToPortraitOnIPad()
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

    /// iPad's regular width renders rows in a `LazyVStack`, not a native `List`, so
    /// `.swipeActions` never existed there — `.contextMenu` (long-press) is the reveal path on
    /// both iPad and macOS (right-click), while iPhone's compact width uses `.swipeActions`.
    private func tapDelete(on row: XCUIElement, app: XCUIApplication) {
        #if os(macOS)
        row.rightClick()
        // Window-scoped, not `app.descendants`: the system Edit menu's standard "Delete" item
        // (identifier `delete:`) also matches an unscoped query, unlike our own `trash`-identified
        // item, which only lives under the window.
        app.windows.firstMatch.descendants(matching: .any)["Delete"].tap()
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            row.press(forDuration: 1.0)
        } else {
            row.swipeLeft()
        }
        app.buttons["Delete"].tap()
        #endif
    }

    func testCancellingTheConfirmationKeepsTheCodebase() throws {
        let app = XCUIApplication()
        let codebaseRow = openSeededCodebaseRow(app)
        tapDelete(on: codebaseRow, app: app)

        #if os(macOS)
        // Scoped to `app.sheets`, not `app.buttons`/`app.descendants`: the Touch Bar exposes its
        // own duplicate "Cancel"-titled button at the same time, which an unscoped query matches
        // ambiguously.
        let cancelButton = app.sheets.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()
        #else
        // At this window size, `.confirmationDialog` renders as a popover with no "Cancel" button
        // at all — tap-outside-to-dismiss (`PopoverDismissRegion`) is this presentation's Cancel.
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5))
        dismissRegion.tap()
        #endif

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
