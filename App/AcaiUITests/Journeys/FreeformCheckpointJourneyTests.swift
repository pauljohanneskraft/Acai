import XCTest

/// Drives the checkpoint save→mutate→restore journey through the UI, using point-and-place
/// catalog insertion (tap a catalog entry, then the canvas, to commit a node) to add nodes.
@MainActor
final class FreeformCheckpointJourneyTests: UIJourneyTestCase {
    private let freeformDiagramID = "33333333-3333-3333-3333-333333333333"

    func testAddNodeSaveCheckpointMutateThenRestore() throws {
        let detail = openSeededProject(analysis: .parsed)
        let diagramRow = detail.freeformDiagramRow(id: freeformDiagramID)
        diagramRow.tapWhenReady("the seeded freeform diagram's row")
        diagramRow.waitForDisappearanceOrFail("the project screen after opening the freeform diagram")

        let screen = FreeformDiagramScreen(app: app)

        // Tapping a catalog entry enters placement mode (ghost + cancel affordance appear)
        // instead of inserting immediately; the next canvas tap commits it.
        screen.placeNodeViaCatalog(kindID: "type.class")

        let newClass = screen.typeNode(named: "NewClass")
        newClass.waitOrFail("the placed class node")
        screen.cancelPlacementButton.waitForDisappearanceOrFail("placement mode after committing the placement")

        screen.saveCheckpoint(named: "Baseline")
        screen.checkpointRow(named: "Baseline").waitOrFail("the Baseline checkpoint row")
        screen.checkpointsDoneButton.tapWhenReady("the checkpoints Done button")

        screen.placeNodeViaCatalog(kindID: "type.enum")

        let newEnum = screen.typeNode(named: "NewEnum")
        newEnum.waitOrFail("the placed enum node")
        XCTAssertTrue(newClass.exists, "the baseline node should still be present right after the mutation")

        screen.tapCheckpoints()
        screen.checkpointRestoreButton(named: "Baseline").tapWhenReady("the Baseline checkpoint's Restore")

        newEnum.waitForDisappearanceOrFail("the node added after the checkpoint, after restoring")
        XCTAssertTrue(newClass.exists, "the baseline node should be back after restoring")
    }
}
