import XCTest

/// Golden screenshots for the two "New ..." sheets not covered by any existing journey:
/// `NewProjectSheet`'s empty form, and `NewCodebaseSheet`'s local-folder tab (the default tab,
/// distinct from the GitHub tab already exercised by `GitHubSignInTests`/`GitHubAddCodebaseTests`).
/// The local tab's "Choose…" button opens a real system file picker (`NSOpenPanel`/document
/// picker), which XCUITest can't drive without further plumbing — this only captures the tab's
/// empty state, not a "directory chosen" state.
@MainActor
final class NewSheetsScreenshotTests: UIJourneyTestCase {

    func testNewProjectSheetScreenshot() throws {
        let browser = launchSeeded(analysis: .parsed)
        let sheet = NewProjectSheetScreen(app: app)
        browser.newProjectButton.tap("New Project", until: sheet.titleField)
        validateScreenshot("NewProjectSheet", state: "empty")
    }

    func testNewCodebaseSheetLocalTabScreenshot() throws {
        let detail = openSeededProject(analysis: .parsed)
        detail.tapAddCodebase()

        let sheet = NewCodebaseSheetScreen(app: app)
        sheet.localNameField.waitOrFail("the new codebase sheet's name field")
        validateScreenshot("NewCodebaseSheet", state: "localTabEmpty")
    }
}
