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
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testReindexingAnUnreachableFolderOffersToChooseAnother() throws {
        let unreachable = "/private/var/AcaiUITestMissing-\(UUID().uuidString)"
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded") { _, destination in
            let projectFile = destination
                .appendingPathComponent("projects/\(Self.projectID).json")
            let seeded = try String(contentsOf: projectFile, encoding: .utf8)
            try seeded
                .replacingOccurrences(of: "\(destination.path)/SampleSwiftPackage", with: unreachable)
                .write(to: projectFile, atomically: true, encoding: .utf8)
        }

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))

        let codebaseDetail = CodebaseDetailScreen(app: app)
        codebaseRow.tapUntil(codebaseDetail.reindexButton)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10))
        codebaseDetail.reindexButton.tap()

        #if os(macOS)
        let alert = app.sheets
        #else
        let alert = app.alerts
        #endif
        let chooseFolderButton = alert.buttons["Choose Folder…"]
        XCTAssertTrue(
            chooseFolderButton.waitForExistence(timeout: 30),
            "An unreachable codebase folder must offer to choose another one.")
        // macOS exposes an alert's message as the element's `value`, iOS as its `label`.
        let expected = "\"\(unreachable)\" is no longer available"
        let message = alert.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected))
            .firstMatch
        XCTAssertTrue(
            message.exists,
            "The alert must say the folder can't be reached, not report it as a codebase with nothing in it.")

        // Leaves the app in a clean state for the next test rather than with a picker open.
        alert.buttons["Cancel"].tap()
    }
}
