import CoreGraphics
import Foundation
import Testing
@testable import AcaiApp

/// `FreeformDiagramViewModel`'s checkpoint methods (B27): that save/restore/delete round-trip
/// through the real `ProjectStore`, and that restoring is a single undoable step.
@Suite("Freeform Diagram Checkpoints (view model)")
@MainActor
struct FreeformDiagramViewModelCheckpointTests {

    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-freeform-checkpoint-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    /// `FreeformDiagramViewModel.browserModel` is `weak` (the app relies on the environment object
    /// owning it), so a test must keep its own strong reference to the returned `ProjectBrowserViewModel`
    /// for as long as the view model is used — otherwise persistence calls silently no-op.
    private func configuredViewModel(
        store: ProjectStore, diagramID: UUID
    ) -> (viewModel: FreeformDiagramViewModel, browserModel: ProjectBrowserViewModel) {
        let browserModel = ProjectBrowserViewModel(store: store)
        let viewModel = FreeformDiagramViewModel()
        viewModel.configure(diagramID: diagramID, browserModel: browserModel)
        return (viewModel, browserModel)
    }

    private func seededDiagram(in store: ProjectStore) -> FreeformDiagram {
        var project = Project(title: "Demo", subtitle: "")
        let diagram = FreeformDiagram(name: "Sketch")
        project.freeformDiagramIDs = [diagram.id]
        store.projects.append(project)
        store.saveProject(project)
        store.saveFreeformDiagram(diagram)
        return diagram
    }

    @Test("Saving a checkpoint persists it to the store and survives a reload")
    func savedCheckpointPersists() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let diagram = seededDiagram(in: store)

            let (viewModel, browserModel) = configuredViewModel(store: store, diagramID: diagram.id)
            viewModel.addNode(kind: .actor, name: "A", at: .zero)
            viewModel.saveCheckpoint(named: "Checkpoint 1")

            #expect(viewModel.checkpoints.map(\.name) == ["Checkpoint 1"])
            #expect(browserModel.store === store)

            let reloaded = ProjectStore(baseDir: dir)
            #expect(reloaded.freeformDiagrams[diagram.id]?.checkpoints.map(\.name) == ["Checkpoint 1"])
        }
    }

    @Test("Restoring a checkpoint replaces the canvas and is a single undo step")
    func restoringCheckpointIsUndoable() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let diagram = seededDiagram(in: store)

            let (viewModel, browserModel) = configuredViewModel(store: store, diagramID: diagram.id)
            #expect(browserModel.store === store)
            viewModel.addNode(kind: .actor, name: "A", at: .zero)
            viewModel.saveCheckpoint(named: "Snapshot")
            let checkpointID = viewModel.checkpoints[0].id
            viewModel.addNode(kind: .actor, name: "B", at: CGPoint(x: 50, y: 50))
            #expect(viewModel.nodes.map(\.name).sorted() == ["A", "B"])

            viewModel.restoreCheckpoint(checkpointID)
            #expect(viewModel.nodes.map(\.name) == ["A"])

            viewModel.undo()
            #expect(viewModel.nodes.map(\.name).sorted() == ["A", "B"])
        }
    }

    @Test("Deleting a checkpoint removes it from the store")
    func deletingCheckpointPersists() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let diagram = seededDiagram(in: store)

            let (viewModel, browserModel) = configuredViewModel(store: store, diagramID: diagram.id)
            #expect(browserModel.store === store)
            viewModel.saveCheckpoint(named: "Snapshot")
            let checkpointID = viewModel.checkpoints[0].id

            viewModel.deleteCheckpoint(checkpointID)

            #expect(viewModel.checkpoints.isEmpty)
            #expect(store.freeformDiagrams[diagram.id]?.checkpoints.isEmpty == true)
        }
    }
}
