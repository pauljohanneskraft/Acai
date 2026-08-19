import XCTest

/// Drives the checkpoint save→mutate→restore journey through the UI, using point-and-place
/// catalog insertion (tap a catalog entry, then the canvas, to commit a node) to add nodes.
@MainActor
final class FreeformCheckpointJourneyTests: UIJourneyTestCase {
    private static let projectID = "11111111-1111-1111-1111-111111111111"
    private static let freeformDiagramID = "33333333-3333-3333-3333-333333333333"

    func testAddNodeSaveCheckpointMutateThenRestore() throws {
        app.rotateToPortraitOnIPad()
        app.launchWithFixture("seeded")

        let browser = ProjectBrowserScreen(app: app)
        let projectRow = browser.projectRow(id: Self.projectID)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10))
        projectRow.tap()

        let detail = ProjectDetailScreen(app: app)
        let diagramRow = detail.freeformDiagramRow(id: Self.freeformDiagramID)
        XCTAssertTrue(diagramRow.waitForExistence(timeout: 10))
        diagramRow.tap()

        let screen = FreeformDiagramScreen(app: app)

        // Tapping a catalog entry enters placement mode (ghost + cancel affordance appear)
        // instead of inserting immediately; the next canvas tap commits it.
        screen.placeNodeViaCatalog(kindID: "type.class")

        let newClass = screen.typeNode(named: "NewClass")
        XCTAssertTrue(newClass.waitForExistence(timeout: 10), "committing a placement should insert the node")
        XCTAssertFalse(screen.cancelPlacementButton.exists, "committing a placement should leave placement mode")

        screen.saveCheckpoint(named: "Baseline")
        XCTAssertTrue(screen.checkpointRow(named: "Baseline").waitForExistence(timeout: 5))
        screen.checkpointsDoneButton.tap()

        screen.placeNodeViaCatalog(kindID: "type.enum")

        let newEnum = screen.typeNode(named: "NewEnum")
        XCTAssertTrue(newEnum.waitForExistence(timeout: 10))
        XCTAssertTrue(newClass.exists, "the baseline node should still be present right after the mutation")

        screen.tapCheckpoints()
        let restoreButton = screen.checkpointRestoreButton(named: "Baseline")
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 10))
        restoreButton.tapWhenHittable()

        XCTAssertTrue(newClass.waitForExistence(timeout: 10), "the baseline node should be back after restoring")
        XCTAssertFalse(newEnum.exists, "the node added after the checkpoint should be gone after restoring")
    }
}
