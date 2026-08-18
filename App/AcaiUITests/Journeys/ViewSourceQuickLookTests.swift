import XCTest

/// End-to-end coverage confirming tapping "View Source" on a `ViolationRowView` opens the target
/// file in Quick Look. The seeded fixture's
/// `SampleSwiftPackage` codebase is wired to `Fixtures/seeded/quality.yml` (a budget with `max: 0`
/// that trips on any method at all), guaranteeing at least one Quality Check finding to exercise
/// this against, without needing a bespoke non-seeded fixture just to produce a violation.
@MainActor
final class ViewSourceQuickLookTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testViewSourceOpensQuickLook() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded") { app, destination in
            app.launchArguments += [
                "-AcaiUITestCodebaseArtifact", Self.codebaseID,
                destination.appendingPathComponent("artifacts/seeded.json").path
            ]
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

        let viewSourceButton = app.buttons["violation.viewSourceButton"].firstMatch
        XCTAssertTrue(viewSourceButton.waitForExistence(timeout: 30))
        viewSourceButton.tap()

        let dismissButton = app.buttons["sourceViewer.dismissButton"]
        XCTAssertTrue(
            dismissButton.waitForExistence(timeout: 10),
            "Quick Look sheet's Done button never appeared — View Source didn't open a viewer.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "QuickLookSheetOpen"
        attachment.lifetime = .keepAlways
        add(attachment)
        dismissButton.tap()
    }
}
