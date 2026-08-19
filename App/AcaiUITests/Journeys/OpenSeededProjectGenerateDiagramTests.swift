import XCTest

@MainActor
final class OpenSeededProjectGenerateDiagramTests: UIJourneyTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let codebaseID = "22222222-2222-2222-2222-222222222222"

    func testGenerateClassDiagramFromSeededCodebase() throws {
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
        codebaseDetail.reindexButton.tap()

        let classDiagramButton = codebaseDetail.diagramButton(type: "class")
        XCTAssertTrue(classDiagramButton.waitForExistence(timeout: 30), "the codebase never finished indexing")
        let diagram = ClassDiagramScreen(app: app)
        // A single tap, never `tapUntil`: this button calls `diagrams.add`, so a retried tap
        // creates a *second* diagram. `tapUntil` allows the canvas only 3s to render before
        // retrying, which a loaded CI runner loses — the duplicate then shows up as an extra
        // sidebar row and a screenshot that differs run to run.
        classDiagramButton.tapWhenHittable()

        XCTAssertTrue(diagram.typeNode(named: "Base").waitForExistence(timeout: 30))
        XCTAssertTrue(diagram.typeNode(named: "Derived").exists)
    }
}
