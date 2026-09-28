import XCTest
#if os(iOS)
import UIKit
#endif

/// Every distinct deletion presentation, once per platform, in one launch: the row's reveal gesture
/// and its confirmation's Cancel, then the "Delete Codebase…"/"Delete Project…" buttons at the bottom
/// of the detail screens. Cancel has to leave the row alone and confirming has to remove it — never
/// closing without acting, never acting without asking.
@MainActor
final class DeletionJourneyTests: UIJourneyTestCase {
    func testCancellingKeepsTheCodebaseThenItsOwnDeleteButtonRemovesIt() throws {
        let projectDetail = openSeededProject(analysis: .parsed)
        let codebaseRow = projectDetail.codebaseRow(id: seeded.codebaseID)

        revealDelete(on: codebaseRow)
        cancelConfirmation()
        XCTAssertTrue(codebaseRow.exists, "cancelling the confirmation must not delete the codebase")

        let codebaseDetail = openSeededCodebaseDetail(from: projectDetail)
        codebaseDetail.deleteCodebaseButton.tapWhenReady("Delete Codebase…")
        codebaseDetail.deleteCodebaseConfirmButton.tapWhenReady("the codebase delete confirmation")
        codebaseRow.waitForDisappearanceOrFail("the deleted codebase's row")
    }

    /// Its own launch: deleting the project is only reachable from a screen the codebase deletion
    /// above has already navigated away from.
    func testDeleteProjectButtonOnItsOwnDetailScreenRemovesIt() throws {
        let projectDetail = openSeededProject(analysis: .parsed)

        projectDetail.deleteProjectButton.tapWhenReady("Delete Project…")
        projectDetail.deleteProjectConfirmButton.tapWhenReady("the project delete confirmation")

        ProjectBrowserScreen(app: app).projectRow(id: seeded.projectID)
            .waitForDisappearanceOrFail("the deleted project's row")
    }

    private func openSeededCodebaseDetail(from projectDetail: ProjectDetailScreen) -> CodebaseDetailScreen {
        let codebaseDetail = CodebaseDetailScreen(app: app)
        projectDetail.codebaseRow(id: seeded.codebaseID).tap(
            "the seeded codebase's row", until: codebaseDetail.deleteCodebaseButton)
        return codebaseDetail
    }

    /// iPad's regular width renders rows in a `LazyVStack`, not a native `List`, so `.swipeActions`
    /// never existed there — `.contextMenu` (long-press) is the reveal path on both iPad and macOS
    /// (right-click), while iPhone's compact width uses `.swipeActions`.
    private func revealDelete(on row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        row.waitUntilReady("the seeded codebase's row", file: file, line: line)
        SystemBanners().dismiss(file: file, line: line)
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

    private func cancelConfirmation() {
        #if os(macOS)
        // Scoped to `app.sheets`, not `app.buttons`/`app.descendants`: the Touch Bar exposes its
        // own duplicate "Cancel"-titled button at the same time, which an unscoped query matches
        // ambiguously.
        app.sheets.buttons["Cancel"].tapWhenReady("the confirmation's Cancel button")
        #else
        // At this window size, `.confirmationDialog` renders as a popover with no "Cancel" button
        // at all — tap-outside-to-dismiss (`PopoverDismissRegion`) is this presentation's Cancel.
        app.dismissPopover(showing: ProjectDetailScreen(app: app).deleteCodebaseConfirmButton)
        #endif
    }
}
