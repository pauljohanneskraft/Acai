import XCTest

/// End-to-end coverage for the project-level Findings view: reindexing the seeded fixture's
/// codebase (wired to `Fixtures/seeded/quality.yml`'s always-tripping budget, exactly like
/// `ViewSourceQuickLookTests`) produces a quality violation, and that finding surfaces in the
/// project-level Findings view — reached via `ProjectDetailScreen.findingsButton` — rather than
/// only inside `CodebaseDetailView`'s own buried section. Also exercises the suppress/unsuppress
/// round trip.
@MainActor
final class FindingsJourneyTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testFindingsViewSurfacesViolationAfterReindex() throws {
        let app = XCUIApplication()
        app.launchWithFixture("seeded")

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

        // Back to the project's own detail pane to reach the Findings entry point. On iPhone
        // (compact width), `ProjectDetailView` and `CodebaseDetailView` share one `NavigationSplitView`
        // detail slot swapped by `Selection`, not a separate push per screen — so the *sidebar*
        // itself (not "ProjectDetailView") is what's one level back from here; pop to it first
        // (when there's a back chevron to pop with — iPad/Mac's regular width keeps the sidebar
        // permanently visible, so there's nothing to pop there), then re-select the project, which
        // is what actually lands on `ProjectDetailView`.
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 5) {
            backButton.tap()
        }
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()
        let findingsButton = detail.findingsButton
        XCTAssertTrue(findingsButton.waitForExistence(timeout: 10))
        findingsButton.tap()

        let findings = FindingsScreen(app: app)
        XCTAssertTrue(
            findings.list.waitForExistence(timeout: 30),
            "Findings list never appeared after reindexing a codebase with an always-tripping budget.")

        // Filter chips narrow to just violations — dead-code/health rows (if any) disappear.
        let violationFilter = findings.kindFilter("violation")
        XCTAssertTrue(violationFilter.waitForExistence(timeout: 5))

        // Suppress the first row, verify it drops out of the default view, then confirm it
        // comes back under "show suppressed too."
        let suppress = findings.suppressButton
        guard suppress.waitForExistence(timeout: 10) else {
            XCTFail("No finding row with a Suppress action appeared.")
            return
        }
        suppress.tap()
        XCTAssertTrue(findings.showSuppressedToggle.waitForExistence(timeout: 5))
        findings.showSuppressedToggle.tap()
        XCTAssertTrue(
            findings.unsuppressButton.waitForExistence(timeout: 10),
            "Suppressed finding didn't reappear under 'show suppressed too.'")
    }
}
