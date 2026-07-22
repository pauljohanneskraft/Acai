import Foundation
import Testing
@testable import AcaiApp

/// `FreeformDiagram.Checkpoint` (B27): save/restore/delete of a named full node/edge snapshot.
/// Layer 0, per the backlog's own "checkpoint persistence + restore tests" verification.
@Suite("FreeformDiagram Checkpoints")
struct FreeformDiagramCheckpointTests {

    private func node(_ name: String) -> FreeformDiagram.Node {
        FreeformDiagram.Node(name: name, content: .actor)
    }

    @Test("Saving a checkpoint captures the diagram's current nodes and edges")
    func saveCheckpointCapturesCurrentState() {
        var diagram = FreeformDiagram(name: "Demo")
        diagram.nodes = [node("A")]
        diagram.saveCheckpoint(named: "First")

        #expect(diagram.checkpoints.count == 1)
        #expect(diagram.checkpoints[0].name == "First")
        #expect(diagram.checkpoints[0].nodes.map(\.name) == ["A"])
    }

    @Test("Restoring a checkpoint replaces the current nodes and edges")
    func restoreReplacesCurrentState() {
        var diagram = FreeformDiagram(name: "Demo")
        diagram.nodes = [node("A")]
        diagram.saveCheckpoint(named: "Snapshot")

        diagram.nodes = [node("B"), node("C")]
        let checkpointID = diagram.checkpoints[0].id
        diagram.restoreCheckpoint(checkpointID)

        #expect(diagram.nodes.map(\.name) == ["A"])
    }

    @Test("Restoring leaves the checkpoint itself in place for a later restore")
    func restoreDoesNotConsumeCheckpoint() {
        var diagram = FreeformDiagram(name: "Demo")
        diagram.nodes = [node("A")]
        diagram.saveCheckpoint(named: "Snapshot")
        let checkpointID = diagram.checkpoints[0].id

        diagram.nodes = [node("B")]
        diagram.restoreCheckpoint(checkpointID)
        diagram.nodes = [node("C")]
        diagram.restoreCheckpoint(checkpointID)

        #expect(diagram.checkpoints.count == 1)
        #expect(diagram.nodes.map(\.name) == ["A"])
    }

    @Test("Restoring a nonexistent checkpoint id is a no-op")
    func restoreUnknownIDIsNoOp() {
        var diagram = FreeformDiagram(name: "Demo")
        diagram.nodes = [node("A")]

        diagram.restoreCheckpoint(UUID())

        #expect(diagram.nodes.map(\.name) == ["A"])
    }

    @Test("Deleting a checkpoint removes only that one")
    func deleteRemovesOnlyThatCheckpoint() {
        var diagram = FreeformDiagram(name: "Demo")
        diagram.saveCheckpoint(named: "First")
        diagram.saveCheckpoint(named: "Second")
        let firstID = diagram.checkpoints[0].id

        diagram.deleteCheckpoint(firstID)

        #expect(diagram.checkpoints.map(\.name) == ["Second"])
    }

    @Test("A freeform diagram saved before checkpoints existed still decodes")
    func decodesLegacyJSONWithoutCheckpointsKey() throws {
        let json = Data("""
        {"id":"\(UUID().uuidString)","name":"Old","nodes":[],"edges":[],
         "canvasScale":1,"canvasOffsetX":0,"canvasOffsetY":0,
         "createdDate":0,"lastModified":0}
        """.utf8)

        let decoded = try JSONDecoder().decode(FreeformDiagram.self, from: json)

        #expect(decoded.name == "Old")
        #expect(decoded.checkpoints.isEmpty)
    }

    @Test("Multiple checkpoints round-trip through Codable")
    func checkpointsRoundTripThroughCodable() throws {
        var diagram = FreeformDiagram(name: "Demo")
        diagram.nodes = [node("A")]
        diagram.saveCheckpoint(named: "First")

        let data = try JSONEncoder().encode(diagram)
        let decoded = try JSONDecoder().decode(FreeformDiagram.self, from: data)

        #expect(decoded.checkpoints.count == 1)
        #expect(decoded.checkpoints[0].name == "First")
        #expect(decoded.checkpoints[0].nodes.map(\.name) == ["A"])
    }
}
