import XCTest

/// #178: the app must never claim freshness (or staleness) it can't substantiate, and must never
/// silently keep showing stale results. The core detection — comparing the fingerprint captured at
/// index time against the code's current state, and flipping to stale after an on-disk edit — is
/// covered directly at the `ProjectBrowserViewModel` layer (`CodebaseFreshnessViewModelTests`), the
/// same split `CompareGitRevisionTests` already uses for its own git-comparison logic. This journey
/// only verifies the banner renders (or doesn't) correctly once that state exists.
@MainActor
final class StaleAnalysisJourneyTests: UIJourneyTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testNoBannerBeforeIndexingOrRightAfterAFreshReindex() throws {
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        let codebaseRow = detail.codebaseRow(id: Self.codebaseID)
        XCTAssertTrue(codebaseRow.waitForExistence(timeout: 10))
        codebaseRow.tap()

        let codebaseDetail = CodebaseDetailScreen(app: app)
        XCTAssertTrue(codebaseDetail.reindexButton.waitForExistence(timeout: 10))
        XCTAssertFalse(
            codebaseDetail.staleBanner.exists,
            "A codebase that has never been indexed has no baseline to compare against — it must read"
                + " as unknown, never as stale."
        )

        codebaseDetail.reindexButton.tap()
        XCTAssertTrue(codebaseDetail.reindexLoadedIndicator.waitForExistence(timeout: 30))

        XCTAssertFalse(
            codebaseDetail.staleBanner.exists,
            "The code on disk hasn't changed since this reindex — the banner must not show."
        )
    }
}
