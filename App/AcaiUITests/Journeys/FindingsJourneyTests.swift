import XCTest

/// Reindexing the seeded fixture's codebase (wired to `Fixtures/seeded/quality.yml`'s
/// always-tripping budget, exactly like `ViewSourceQuickLookTests`) produces a quality violation
/// that should surface in the project-level Findings view, not just `CodebaseDetailView`'s own
/// section. Also exercises the suppress/unsuppress round trip.
@MainActor
final class FindingsJourneyTests: UIJourneyTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testFindingsViewSurfacesViolationAfterReindex() throws {
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

        // On iPhone, `ProjectDetailView` and `CodebaseDetailView` share one `NavigationSplitView`
        // detail slot swapped by `Selection`, not a separate push per screen, so the sidebar (not
        // "ProjectDetailView") is one level back from here; pop to it (iPad/Mac's regular width
        // keeps the sidebar visible, so there's nothing to pop there), then re-select the project.
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 5) {
            backButton.tap()
        }
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        // In-flight reindex completion can rebuild the sidebar and invalidate `projectRow` mid-tap.
        projectRow.tapUntil(detail.findingsButton)
        let findingsButton = detail.findingsButton
        XCTAssertTrue(findingsButton.waitForExistence(timeout: 10))
        findingsButton.tap()

        let findings = FindingsScreen(app: app)
        XCTAssertTrue(
            findings.list.waitForExistence(timeout: 30),
            "Findings list never appeared after reindexing a codebase with an always-tripping budget.")

        let violationFilter = findings.kindFilter("violation")
        XCTAssertTrue(violationFilter.waitForExistence(timeout: 5))

        let row = findings.firstViolationRow
        guard row.waitForExistence(timeout: 10) else {
            XCTFail("No finding row appeared.")
            return
        }
        let suppress = findings.suppressButton(in: row)
        XCTAssertTrue(suppress.waitForExistence(timeout: 10), "No finding row with a Suppress action appeared.")
        suppress.tap()
        XCTAssertTrue(findings.showSuppressedToggle.waitForExistence(timeout: 5))
        findings.showSuppressedToggle.tap()
        XCTAssertTrue(
            findings.unsuppressButton(in: row).waitForExistence(timeout: 10),
            "Suppressed finding didn't reappear under 'show suppressed too.'")
    }
}
