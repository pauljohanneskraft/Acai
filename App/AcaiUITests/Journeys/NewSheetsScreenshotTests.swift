import XCTest

/// Golden screenshots for the two "New ..." sheets not covered by any existing journey:
/// `NewProjectSheet`'s empty form, and `NewCodebaseSheet`'s local-folder tab (the default tab,
/// distinct from the GitHub tab already exercised by `GitHubSignInTests`/`GitHubAddCodebaseTests`).
/// The local tab's "Choose…" button opens a real system file picker (`NSOpenPanel`/document
/// picker), which XCUITest can't drive without further plumbing — this only captures the tab's
/// empty state, not a "directory chosen" state.
@MainActor
final class NewSheetsScreenshotTests: UIJourneyTestCase {

    /// One launch for all three states: creating the project is what produces the empty state, and the
    /// empty state's own prompt is what opens the codebase sheet, so each capture is a step of the flow
    /// that leads to the next rather than a launch of its own.
    func testTheNewProjectAndCodebaseSheetsAndTheEmptyStateBetweenThem() throws {
        let browser = launchSeeded()
        let projectSheet = NewProjectSheetScreen(app: app)
        browser.newProjectButton.tap("New Project", until: projectSheet.titleField)
        validateScreenshot("NewProjectSheet", state: "empty")

        projectSheet.create(title: "Empty")
        let detail = ProjectDetailScreen(app: app)
        detail.emptyState.waitOrFail("the empty project's add prompt")
        validateScreenshot("ProjectDetail", state: "empty")

        let codebaseSheet = NewCodebaseSheetScreen(app: app)
        detail.addCodebaseButton.tap("the empty project's Add Codebase prompt", until: codebaseSheet.localNameField)
        validateScreenshot("NewCodebaseSheet", state: "localTabEmpty")
    }
}
