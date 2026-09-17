import XCTest

@MainActor
final class StaleAnalysisJourneyTests: UIJourneyTestCase {

    func testNoBannerBeforeIndexingOrRightAfterAFreshReindex() throws {
        let codebaseDetail = openSeededCodebase(analysis: .parsed)
        XCTAssertFalse(
            codebaseDetail.staleBanner.exists,
            "A codebase that has never been indexed has no baseline to compare against — it must read"
                + " as unknown, never as stale."
        )

        codebaseDetail.reindex()

        XCTAssertFalse(
            codebaseDetail.staleBanner.exists,
            "The code on disk hasn't changed since this reindex — the banner must not show."
        )
    }
}
