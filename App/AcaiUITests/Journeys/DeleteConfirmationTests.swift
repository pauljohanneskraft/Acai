import XCTest
#if os(iOS)
import UIKit
#endif

/// Verifies the codebase-delete confirmation dialog: cancel/confirm both actually do what they say,
/// never just closing the sheet without acting or acting without asking. Each test launches its own
/// fresh copy of the fixture, so a confirmed deletion in one test never affects another.
@MainActor
final class DeleteConfirmationTests: UIJourneyTestCase {

    private func openSeededCodebaseRow() -> XCUIElement {
        openSeededProject(analysis: .parsed).codebaseRow(id: seeded.codebaseID)
    }

    /// iPad's regular width renders rows in a `LazyVStack`, not a native `List`, so
    /// `.swipeActions` never existed there — `.contextMenu` (long-press) is the reveal path on
    /// both iPad and macOS (right-click), while iPhone's compact width uses `.swipeActions`.
    private func tapDelete(on row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        row.waitUntilReady("the seeded codebase's row", file: file, line: line)
        #if os(macOS)
        row.rightClick()
        // Window-scoped, not `app.descendants`: the system Edit menu's standard "Delete" item
        // (identifier `delete:`) also matches an unscoped query, unlike our own `trash`-identified
        // item, which only lives under the window.
        let delete = app.windows.firstMatch.descendants(matching: .any)["Delete"]
        #else
        let delete = app.buttons["Delete"]
        if UIDevice.current.userInterfaceIdiom == .pad {
            row.press(forDuration: 1.5)
        } else {
            row.swipeLeft()
        }
        #endif
        delete.tapWhenReady(
            "the row's Delete action (if the codebase screen opened instead, the reveal gesture registered as a tap)",
            file: file, line: line
        )
    }

    func testCancellingTheConfirmationKeepsTheCodebase() throws {
        let codebaseRow = openSeededCodebaseRow()
        tapDelete(on: codebaseRow)

        #if os(macOS)
        // Scoped to `app.sheets`, not `app.buttons`/`app.descendants`: the Touch Bar exposes its
        // own duplicate "Cancel"-titled button at the same time, which an unscoped query matches
        // ambiguously.
        app.sheets.buttons["Cancel"].tapWhenReady("the confirmation's Cancel button")
        #else
        // At this window size, `.confirmationDialog` renders as a popover with no "Cancel" button
        // at all — tap-outside-to-dismiss (`PopoverDismissRegion`) is this presentation's Cancel.
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        dismissRegion.tapWhenReady("the confirmation popover's dismiss region")
        dismissRegion.waitForDisappearanceOrFail("the confirmation popover")
        #endif

        XCTAssertTrue(codebaseRow.exists, "cancelling the confirmation must not delete the codebase")
    }

    func testConfirmingTheConfirmationRemovesTheCodebase() throws {
        let codebaseRow = openSeededCodebaseRow()
        tapDelete(on: codebaseRow)

        ProjectDetailScreen(app: app).deleteCodebaseConfirmButton.tapWhenReady("the delete confirmation")

        codebaseRow.waitForDisappearanceOrFail("the deleted codebase's row")
    }
}
