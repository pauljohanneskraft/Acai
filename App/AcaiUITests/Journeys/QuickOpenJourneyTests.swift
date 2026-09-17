import XCTest

/// Selection-routing logic is covered by `QuickOpenControllerTests`; this only proves the sheet
/// opens, search filters, and tapping a result actually navigates.
@MainActor
final class QuickOpenJourneyTests: UIJourneyTestCase {

    func testSearchingAndSelectingACodebaseNavigatesToIt() throws {
        launchSeeded(analysis: .parsed).openQuickOpen()

        let quickOpen = QuickOpenScreen(app: app)
        quickOpen.searchField.waitOrFail("the Quick Open search field")
        // Search filters only on query changes, not once the index finishes building — typing before
        // `buildIndex()` completes would filter an empty list and never re-run.
        quickOpen.loadingState.waitForDisappearanceOrFail("Quick Open's loading state")

        let result = quickOpen.result(id: "codebase:\(seeded.codebaseID)")
        quickOpen.search("SampleSwiftPackage", until: result)

        let codebaseDetail = CodebaseDetailScreen(app: app)
        result.tap("the seeded codebase's Quick Open result", until: codebaseDetail.reindexButton)
    }
}
