import XCTest

/// Content (churn/complexity math, the three `HotspotViewModel.load` branches) is covered by
/// `HotspotViewModelTests`; this only proves the screen opens and its toolbar responds.
@MainActor
final class HotspotJourneyTests: UIJourneyTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testHotspotScreenOpensAndTogglesItsSidebar() throws {
        app.launchWithFixture("seeded") { app, destination in
            app.launchEnvironment["ACAI_UITEST_CODEBASE_ARTIFACTS"] = app.environmentRecords([
                [Self.codebaseID, destination.appendingPathComponent("artifacts/seeded.json").path]
            ])
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

        let hotspotButton = codebaseDetail.diagramButton(type: "hotspot")
        XCTAssertTrue(hotspotButton.waitForExistence(timeout: 30))
        let hotspot = HotspotScreen(app: app)
        hotspotButton.tapUntil(hotspot.sidebarToggleButton)

        // The seeded fixture isn't a git repository, so this lands on the "no git history" status
        // state rather than a populated chart — either way, loading finished without hanging.
        XCTAssertTrue(hotspot.loadingIndicator.waitForNonExistence(timeout: 15))

        hotspot.sidebarToggleButton.tap()
    }
}
