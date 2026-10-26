import XCTest

/// Every distinct deletion presentation, once per platform, in one launch: the row's reveal gesture
/// and its confirmation's Cancel, the Mac sidebar selection's ⌫, then the "Delete Codebase…"/"Delete
/// Project…" buttons at the bottom of the detail screens. Cancel has to leave the row alone and
/// confirming has to remove it — never closing without acting, never acting without asking.
@MainActor
final class DeletionJourneyTests: UIJourneyTestCase {
    func testCancellingKeepsTheCodebaseThenItsOwnDeleteButtonRemovesIt() throws {
        let projectDetail = openSeededProject(analysis: .parsed)
        let codebaseRow = projectDetail.codebaseRow(id: seeded.codebaseID)

        RowDeleteAffordance(app: app).tapDelete(on: codebaseRow, "the seeded codebase's row")
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
        let browser = ProjectBrowserScreen(app: app)

        // macOS only: iPadOS does not deliver an unmodified ⌫ to a SwiftUI `keyboardShortcut`.
        #if os(macOS)
        browser.deleteCodebaseWithKeyboard(
            browser.codebaseRow(id: seeded.codebaseID),
            until: CodebaseDetailScreen(app: app).deleteCodebaseButton)
        browser.projectRow(id: seeded.projectID)
            .tap("the seeded project's sidebar row", until: projectDetail.deleteProjectButton)
        #endif

        projectDetail.deleteProjectButton.tapWhenReady("Delete Project…")
        projectDetail.deleteProjectConfirmButton.tapWhenReady("the project delete confirmation")

        browser.projectRow(id: seeded.projectID)
            .waitForDisappearanceOrFail("the deleted project's row")

        // The fixture holds exactly one project, so deleting it is also the only way to reach the
        // zero-projects sidebar. Deletion leaves `model.selection` pointing at the project that is
        // gone, so compact width keeps its detail screen pushed over the sidebar — that is what
        // `emptyProjectPlaceholder` renders — and the sidebar is reached by going back.
        if SnapshotPlatform().usesCompactLayout {
            browser.backButton.tap("Back to the sidebar", until: browser.emptyState)
        }
        browser.emptyState.waitOrFail("the sidebar's no-projects state")
        validateScreenshot("ProjectBrowser", state: "noProjects")

        // Compact width has no footer New Project button, so this state's own button is the only
        // way out of an empty sidebar there.
        browser.emptyStateNewProjectButton.tap(
            "the empty sidebar's New Project button", until: NewProjectSheetScreen(app: app).titleField)
    }

    private func openSeededCodebaseDetail(from projectDetail: ProjectDetailScreen) -> CodebaseDetailScreen {
        let codebaseDetail = CodebaseDetailScreen(app: app)
        projectDetail.codebaseRow(id: seeded.codebaseID).tap(
            "the seeded codebase's row", until: codebaseDetail.deleteCodebaseButton)
        return codebaseDetail
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
