import Foundation
import Testing
import AcaiQuality
@testable import AcaiApp

@Suite("Diagram create from selection")
@MainActor
struct DiagramCreateFromSelectionTests {
    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-diagram-create-from-selection-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test func creatingFromSelectionPinsAFreshClassDiagramToExactlyThoseIDs() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let codebaseID = UUID()
            let originalID = model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .classDiagram(.init()))!
            model.diagrams.updatePositions(
                diagramID: originalID,
                positions: ["A": CGPoint(x: 1, y: 2), "B": CGPoint(x: 3, y: 4)],
                sizes: ["A": CGSize(width: 5, height: 6), "B": CGSize(width: 7, height: 8)],
                scale: 2, offset: CGPoint(x: 9, y: 10)
            )

            let newID = model.diagrams.createDiagramFromSelection(originalID, selectedNodeIDs: ["A"])

            #expect(newID != nil)
            #expect(newID != originalID)
            let original = store.generatedDiagrams[originalID]!
            let scoped = store.generatedDiagrams[newID!]!
            guard case .classDiagram(let config) = scoped.content else {
                Issue.record("expected a class diagram")
                return
            }
            #expect(config.filter == AcaiQuality.Selector(explicitIDs: ["A"]))
            #expect(scoped.codebaseID == original.codebaseID)
            #expect(scoped.nodePositions == ["A": .init(point: CGPoint(x: 1, y: 2))])
            #expect(scoped.nodeSizes == ["A": .init(size: CGSize(width: 5, height: 6))])
            #expect(original.hasSavedFraming)
            #expect(!scoped.hasSavedFraming, "the original's framing doesn't frame the subset")
            #expect(scoped.isNameUserDefined)
            #expect(store.projects.first?.generatedDiagramIDs.contains(newID!) == true)
            #expect(store.projects.first?.generatedDiagramIDs.contains(originalID) == true)
            // The original is untouched.
            #expect(original.content == .classDiagram(.init()))
        }
    }

    @Test func creatingFromAnEmptySelectionIsANoOp() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let originalID = model.diagrams.add(to: projectID, codebaseID: UUID(), content: .classDiagram(.init()))!

            let newID = model.diagrams.createDiagramFromSelection(originalID, selectedNodeIDs: [])

            #expect(newID == nil)
            #expect(store.generatedDiagrams.count == 1)
        }
    }

    @Test func creatingFromSelectionOnAMissingDiagramIDIsANoOp() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            _ = model.editing.addProject(title: "Demo", subtitle: "")

            let newID = model.diagrams.createDiagramFromSelection(UUID(), selectedNodeIDs: ["A"])

            #expect(newID == nil)
            #expect(store.generatedDiagrams.isEmpty)
        }
    }

    @Test func creatingFromSelectionOnADiagramTypeWithNoFilterConceptIsANoOp() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let originalID = model.diagrams.add(to: projectID, codebaseID: UUID(), content: .packageDiagram)!

            let newID = model.diagrams.createDiagramFromSelection(originalID, selectedNodeIDs: ["A"])

            #expect(newID == nil)
            #expect(store.generatedDiagrams.count == 1)
        }
    }

    @Test func creatingAFreeformDiagramFromSelectionKeepsOnlySelectedNodesAndFullyInternalEdges() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let originalID = model.freeforms.add(to: projectID, name: "Sketch")!
            var diagram = store.freeformDiagrams[originalID]!
            diagram.nodes = [
                .init(id: "A", name: "A", content: .actor),
                .init(id: "B", name: "B", content: .actor),
                .init(id: "C", name: "C", content: .actor)
            ]
            diagram.edges = [
                .init(id: "e1", sourceNodeID: "A", targetNodeID: "B", kind: .association),
                .init(id: "e2", sourceNodeID: "B", targetNodeID: "C", kind: .association)
            ]
            diagram.checkpoints = [.init(name: "Snap", nodes: diagram.nodes, edges: diagram.edges)]
            model.freeforms.update(diagramID: originalID, diagram: diagram)

            let newID = model.freeforms.createDiagramFromSelection(originalID, selectedNodeIDs: ["A", "B"])

            #expect(newID != nil)
            let scoped = store.freeformDiagrams[newID!]!
            #expect(scoped.nodes.map(\.id).sorted() == ["A", "B"])
            #expect(scoped.edges.map(\.id) == ["e1"])
            #expect(scoped.checkpoints.isEmpty)
            #expect(store.projects.first?.freeformDiagramIDs.contains(newID!) == true)
            #expect(store.projects.first?.freeformDiagramIDs.contains(originalID) == true)
            // The original is untouched.
            let original = store.freeformDiagrams[originalID]!
            #expect(original.nodes.count == 3)
            #expect(original.edges.count == 2)
        }
    }

    @Test func creatingAFreeformDiagramFromAnEmptySelectionIsANoOp() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let originalID = model.freeforms.add(to: projectID, name: "Sketch")!

            let newID = model.freeforms.createDiagramFromSelection(originalID, selectedNodeIDs: [])

            #expect(newID == nil)
            #expect(store.freeformDiagrams.count == 1)
        }
    }
}
