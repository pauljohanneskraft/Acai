import XCTest

/// A codebase whose folder the app can't reach — deleted, moved off a volume, or (under the App
/// Sandbox) never re-granted after relaunch — must say so and offer to point the codebase at
/// another folder, not report it as an empty codebase.
///
/// The fixture's `directoryPath` is rewritten to a path that doesn't exist and lies outside every
/// grant the app has. A sandbox *denial* specifically can't be staged here: provoking one means
/// either a real system file picker or a cross-container read that raises an OS prompt, neither of
/// which a headless CI run can drive — but both denial and absence take the same
/// `ScopedResourceAccess.Failure` path into this alert.
@MainActor
final class UnreachableCodebaseRecoveryTests: UIJourneyTestCase {

    func testReindexingAnUnreachableFolderOffersToChooseAnother() throws {
        let unreachable = "/private/var/AcaiUITestMissing-\(UUID().uuidString)"
        let projectID = seeded.projectID
        let browser = launchSeeded(analysis: .parsed) { _, destination in
            let projectFile = destination.appendingPathComponent("projects/\(projectID).json")
            let seeded = try String(contentsOf: projectFile, encoding: .utf8)
            try seeded
                .replacingOccurrences(of: "\(destination.path)/SampleSwiftPackage", with: unreachable)
                .write(to: projectFile, atomically: true, encoding: .utf8)
        }

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: seeded.codebaseID)
        browser.projectRow(id: seeded.projectID).tap("the seeded project's sidebar row", until: codebaseRow)

        let codebaseDetail = CodebaseDetailScreen(app: app)
        codebaseRow.tap("the seeded codebase's row", until: codebaseDetail.reindexButton)
        codebaseDetail.reindexButton.tapWhenReady("Reindex")

        #if os(macOS)
        let alert = app.sheets
        #else
        let alert = app.alerts
        #endif
        let chooseFolderButton = alert.buttons["Choose Folder…"]
        chooseFolderButton.waitOrFail("the unreachable-folder alert's Choose Folder… button", timeout: .uiWork)
        // macOS exposes an alert's message as the element's `value`, iOS as its `label`.
        let expected = "\"\(unreachable)\" is no longer available"
        let message = alert.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected))
            .firstMatch
        XCTAssertTrue(
            message.exists,
            "The alert must say the folder can't be reached, not report it as a codebase with nothing in it.")

        alert.buttons["Cancel"].tapWhenReady("the alert's Cancel button")
    }
}
