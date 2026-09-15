import Foundation
import Testing
@testable import AcaiApp

@Suite("Diagram duplicate")
@MainActor
struct DiagramDuplicateTests {
    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-diagram-duplicate-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test func duplicatingAGeneratedDiagramCreatesAnIndependentCopyWithTheSameArrangement() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let codebaseID = UUID()
            let originalID = model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram)!
            model.diagrams.updatePositions(
                diagramID: originalID, positions: ["A": CGPoint(x: 1, y: 2)], sizes: ["A": CGSize(width: 3, height: 4)],
                scale: 2, offset: CGPoint(x: 5, y: 6)
            )

            let copyID = model.diagrams.duplicate(originalID)

            #expect(copyID != nil)
            #expect(copyID != originalID)
            let original = store.generatedDiagrams[originalID]!
            let copy = store.generatedDiagrams[copyID!]!
            #expect(copy.nodePositions == original.nodePositions)
            #expect(copy.nodeSizes == original.nodeSizes)
            #expect(copy.canvasScale == original.canvasScale)
            #expect(copy.canvasOffsetX == original.canvasOffsetX)
            #expect(copy.canvasOffsetY == original.canvasOffsetY)
            #expect(copy.codebaseID == original.codebaseID)
            #expect(copy.content == original.content)
            #expect(store.projects.first?.generatedDiagramIDs.contains(copyID!) == true)
            #expect(store.projects.first?.generatedDiagramIDs.contains(originalID) == true)
        }
    }

    @Test func renamingTheDuplicateGeneratedDiagramDoesNotChangeTheOriginal() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let codebaseID = UUID()
            let originalID = model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram)!
            let originalName = store.generatedDiagrams[originalID]!.name

            let copyID = model.diagrams.duplicate(originalID)!
            model.diagrams.rename(copyID, name: "Renamed Copy")

            #expect(store.generatedDiagrams[originalID]!.name == originalName)
            #expect(store.generatedDiagrams[copyID]!.name == "Renamed Copy")
        }
    }

    @Test func duplicatingAMissingGeneratedDiagramIDIsANoOp() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            _ = model.editing.addProject(title: "Demo", subtitle: "")

            let copyID = model.diagrams.duplicate(UUID())

            #expect(copyID == nil)
            #expect(store.generatedDiagrams.isEmpty)
        }
    }

    @Test func duplicatingAFreeformDiagramCreatesAnIndependentCopyWithTheSameNodesAndEdges() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let originalID = model.freeforms.add(to: projectID, name: "Sketch")!
            var diagram = store.freeformDiagrams[originalID]!
            diagram.nodes = [.init(name: "Foo", content: .actor, positionX: 10, positionY: 20)]
            model.freeforms.update(diagramID: originalID, diagram: diagram)

            let copyID = model.freeforms.duplicate(originalID)

            #expect(copyID != nil)
            #expect(copyID != originalID)
            let original = store.freeformDiagrams[originalID]!
            let copy = store.freeformDiagrams[copyID!]!
            #expect(copy.nodes == original.nodes)
            #expect(copy.edges == original.edges)
            #expect(copy.canvasScale == original.canvasScale)
            #expect(store.projects.first?.freeformDiagramIDs.contains(copyID!) == true)
            #expect(store.projects.first?.freeformDiagramIDs.contains(originalID) == true)
        }
    }

    @Test func renamingTheDuplicateFreeformDiagramDoesNotChangeTheOriginal() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let originalID = model.freeforms.add(to: projectID, name: "Sketch")!

            let copyID = model.freeforms.duplicate(originalID)!
            model.freeforms.rename(copyID, name: "Renamed Copy")

            #expect(store.freeformDiagrams[originalID]!.name == "Sketch")
            #expect(store.freeformDiagrams[copyID]!.name == "Renamed Copy")
        }
    }

    @Test func duplicatingAMissingFreeformDiagramIDIsANoOp() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            _ = model.editing.addProject(title: "Demo", subtitle: "")

            let copyID = model.freeforms.duplicate(UUID())

            #expect(copyID == nil)
            #expect(store.freeformDiagrams.isEmpty)
        }
    }
}
