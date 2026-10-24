import XCTest

/// Golden screenshots for the two "New ..." sheets not covered by any existing journey:
/// `NewProjectSheet`'s empty form, and `NewCodebaseSheet`'s local-folder tab (the default tab,
/// distinct from the GitHub tab already exercised by `GitHubSignInTests`/`GitHubAddCodebaseTests`) —
/// and then, on the seeded project, the question that tab asks once the picked folder turns out to
/// hold several projects: one codebase per project, or one combined codebase.
///
/// The local tab's "Choose…" button opens a real system file picker (`NSOpenPanel`/document
/// picker), which XCUITest can't drive, so the empty-state capture is all it can take of the picker
/// itself and everything behind a picked folder is reached through a staged one instead
/// (`UITestFixtureResolver.resolveLocalFolderURL()`). That folder is built here rather than bundled
/// as a fixture resource: two throwaway Swift packages are all the walk needs, and staging them
/// outside `Fixtures/seeded` keeps the shared fixture — and every golden taken from it — untouched.
@MainActor
final class NewSheetsScreenshotTests: UIJourneyTestCase {

    /// One launch for all of it: creating the project is what produces the empty state, the empty
    /// state's own prompt is what opens the codebase sheet, and that sheet is where the several-projects
    /// question is answered — each step is what leads to the next rather than a launch of its own.
    func testTheNewSheetsTheEmptyStateAndAFolderOfSeveralProjects() throws {
        let browser = launchSeeded(configure: { app, destination in
            let workspace = destination
                .deletingLastPathComponent()
                .appendingPathComponent("MultiRootWorkspace", isDirectory: true)
            try? FileManager.default.removeItem(at: workspace)
            for name in ["Alpha", "Beta"] {
                let sources = workspace.appendingPathComponent("\(name)/Sources/\(name)", isDirectory: true)
                try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
                try "// swift-tools-version:6.0\n".write(
                    to: workspace.appendingPathComponent("\(name)/Package.swift"),
                    atomically: true, encoding: .utf8)
                try "struct \(name)Service {}\n".write(
                    to: sources.appendingPathComponent("\(name).swift"), atomically: true, encoding: .utf8)
            }
            app.launchEnvironment["ACAI_UITEST_LOCAL_FOLDER"] = workspace.path
        })

        let projectSheet = NewProjectSheetScreen(app: app)
        browser.newProjectButton.tap("New Project", until: projectSheet.titleField)
        validateScreenshot("NewProjectSheet", state: "empty")

        projectSheet.create(title: "Empty")
        let detail = ProjectDetailScreen(app: app)
        detail.emptyState.waitOrFail("the empty project's add prompt")
        validateScreenshot("ProjectDetail", state: "empty")

        let sheet = NewCodebaseSheetScreen(app: app)
        detail.addCodebaseButton.tap("the empty project's Add Codebase prompt", until: sheet.localNameField)
        validateScreenshot("NewCodebaseSheet", state: "localTabEmpty")
        sheet.cancel()

        // One codebase per project: both roots arrive checked, so Add needs no further choice.
        reopenSeededProject(browser, detail)
        detail.tapAddCodebase()
        sheet.chooseStagedFolder()
        sheet.rootToggle("Alpha").waitOrFail("the Alpha project's checkbox")
        sheet.rootToggle("Beta").waitOrFail("the Beta project's checkbox")
        sheet.add()

        // Adding selects the first codebase it created, so the project — and the Add action on it —
        // has to be reopened before the rows it made are both on screen and the folder can be added
        // a second time.
        reopenSeededProject(browser, detail)
        detail.codebaseRow(named: "Alpha").waitOrFail("the Alpha codebase's row")
        detail.codebaseRow(named: "Beta").waitOrFail("the Beta codebase's row")

        // The same folder again, combined this time: one codebase under the typed name.
        detail.tapAddCodebase()
        sheet.chooseStagedFolder()
        sheet.enterLocalName("Everything")
        sheet.flip(sheet.combineRootsToggle, "the Combine into one codebase toggle")
        sheet.add()

        // Adding selects the codebase it created, whose own screen renames it through a text field
        // rather than showing it as a row, so the project is reopened here too.
        reopenSeededProject(browser, detail)
        detail.codebaseRow(named: "Everything").waitOrFail("the combined codebase's row")
    }

    /// Compact width swaps `ProjectDetailView` and `CodebaseDetailView` into one detail slot, so the
    /// sidebar is one level back from whatever the previous step left open; regular width keeps the
    /// sidebar visible and has nothing to pop.
    private func reopenSeededProject(
        _ browser: ProjectBrowserScreen, _ detail: ProjectDetailScreen,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let projectRow = browser.projectRow(id: seeded.projectID)
        if SnapshotPlatform().usesCompactLayout {
            browser.backButton.tap("the navigation back button", until: projectRow, file: file, line: line)
        }
        projectRow.tap(
            "the seeded project's sidebar row", until: detail.codebaseRow(id: seeded.codebaseID),
            file: file, line: line)
    }
}
