import XCTest

/// Covers the "Delete Project…"/"Delete Codebase…" buttons at the bottom of
/// `ProjectDetailView`/`CodebaseDetailView`, a second path to the same action
/// `DeleteConfirmationTests` covers via the sidebar/row context menu.
@MainActor
final class DiscoverableDeletePathTests: UIJourneyTestCase {

    func testDeleteCodebaseButtonOnItsOwnDetailScreenRemovesIt() throws {
        let codebaseDetail = openSeededCodebase(analysis: .parsed)
        let codebaseRow = ProjectDetailScreen(app: app).codebaseRow(id: seeded.codebaseID)

        codebaseDetail.deleteCodebaseButton.tapWhenReady("Delete Codebase…")
        codebaseDetail.deleteCodebaseConfirmButton.tapWhenReady("the codebase delete confirmation")

        codebaseRow.waitForDisappearanceOrFail(
            "the deleted codebase's row (its own delete button must remove it, same as the row's context menu)"
        )
    }

    func testDeleteProjectButtonOnItsOwnDetailScreenRemovesIt() throws {
        let detail = openSeededProject(analysis: .parsed)
        let projectRow = ProjectBrowserScreen(app: app).projectRow(id: seeded.projectID)

        detail.deleteProjectButton.tapWhenReady("Delete Project…")
        detail.deleteProjectConfirmButton.tapWhenReady("the project delete confirmation")

        projectRow.waitForDisappearanceOrFail(
            "the deleted project's row (its own delete button must remove it, same as the sidebar's context menu)"
        )
    }
}
