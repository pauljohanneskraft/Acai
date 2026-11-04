import XCTest

/// The multi-project folder is staged outside `Fixtures/seeded`, so no golden from that fixture changes.
@MainActor
final class NewSheetsScreenshotTests: UIJourneyTestCase {

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
        detail.addCodebaseButton.tap(
            "the empty project's Add Codebase prompt", until: sheet.chooseDirectoryButton)
        validateScreenshot("NewCodebaseSheet", state: "localTabEmpty")
        sheet.cancel()

        reopenSeededProject(browser, detail)
        detail.tapAddCodebase()
        sheet.chooseStagedFolder()
        sheet.rootToggle("Alpha").waitOrFail("the Alpha project's checkbox")
        sheet.rootToggle("Beta").waitOrFail("the Beta project's checkbox")
        sheet.add()

        // Adding selects the new codebase, so the project is reopened to see its rows.
        reopenSeededProject(browser, detail)
        detail.codebaseRow(named: "Alpha").waitOrFail("the Alpha codebase's row")
        detail.codebaseRow(named: "Beta").waitOrFail("the Beta codebase's row")

        detail.tapAddCodebase()
        sheet.chooseStagedFolder()
        sheet.flip(sheet.combineRootsToggle, "the Combine into one codebase toggle")
        sheet.add()

        reopenSeededProject(browser, detail)
        detail.codebaseRow(named: "MultiRootWorkspace").waitOrFail("the combined codebase's row")
    }

    /// Compact width shows the project and codebase screens in one detail slot, so it pops back first.
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
