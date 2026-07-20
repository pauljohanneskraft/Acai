import XCTest

/// The flagship first-slice journey (`TESTING_ARCHITECTURE.md`): open a fixture-seeded project,
/// index its (un-indexed, by design — `Fixtures/seeded`) local-folder codebase, generate a Class
/// Diagram, and verify its nodes actually render.
final class OpenSeededProjectGenerateDiagramTests: XCTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testGenerateClassDiagramFromSeededCodebase() throws {
        let app = XCUIApplication()
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

        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButton.waitForExistence(timeout: 30), "the codebase never finished indexing")
        classDiagramButton.tap()

        let diagram = ClassDiagramScreen(app: app)
        XCTAssertTrue(diagram.typeNode(named: "Base").waitForExistence(timeout: 10))
        XCTAssertTrue(diagram.typeNode(named: "Derived").exists)
    }
}
