import XCTest

/// `QueryView`, scoped to the seeded fixture's `SampleSwiftPackage` codebase: `Base` is the only
/// type with a publicly-settable stored property (`id`) among the fixture's four classes
/// (`Base`, `Derived`, `Helper`, `Worker`) — `Derived.helper`/`Helper.worker` are `private`, and
/// `Worker` has no stored properties at all — so toggling "Mutable public state only" is a real,
/// known-answer filter, not just a smoke check that the screen opens.
@MainActor
final class QueryJourneyTests: UIJourneyTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testQueryViewFiltersByMutablePublicState() throws {
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
        codebaseDetail.reindexButton.tap()

        XCTAssertTrue(
            codebaseDetail.queryButton.waitForExistence(timeout: 30), "the codebase never finished indexing")
        codebaseDetail.queryButton.tap()

        let query = QueryScreen(app: app)
        XCTAssertTrue(query.list.waitForExistence(timeout: 10))
        XCTAssertTrue(query.row(id: "Base").waitForExistence(timeout: 10))
        XCTAssertTrue(query.row(id: "Worker").exists)

        XCTAssertTrue(query.mutablePublicStateToggle.waitForExistence(timeout: 5))
        query.mutablePublicStateToggle.tap()

        XCTAssertTrue(
            query.row(id: "Base").waitForExistence(timeout: 10),
            "Base has a public settable `id` property and should still match.")
        XCTAssertFalse(
            query.row(id: "Worker").exists,
            "Worker has no stored properties at all and shouldn't match \"mutable public state only\".")
        XCTAssertFalse(
            query.row(id: "Derived").exists,
            "Derived's only property (`helper`) is private and shouldn't match.")

        query.clearFiltersButton.tap()
        XCTAssertTrue(query.row(id: "Worker").waitForExistence(timeout: 10), "Clearing filters should restore Worker.")
    }
}
