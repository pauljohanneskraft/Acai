import Foundation
import Testing
import AcaiQuality
@testable import AcaiApp

/// `GeneratedDiagramEditor.openCycle` is issue #192's replacement for the retired standalone Cycle
/// Diagram: opening a dependency cycle now creates a class or package diagram scoped to exactly
/// that cycle's members, reusing the same selector-filter mechanism `createDiagramFromSelection`
/// already established for an arbitrary node selection.
@Suite("Open Cycle as Diagram")
@MainActor
struct OpenCycleDiagramTests {
    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-open-cycle-diagram-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test func typesScopeCycleOpensAsAClassDiagramFilteredToItsMembers() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")

            let id = model.diagrams.openCycle(
                to: projectID, codebaseID: UUID(), scope: .types, members: ["A", "B", "C"])

            #expect(id != nil)
            let diagram = store.generatedDiagrams[id!]!
            guard case .classDiagram(let config) = diagram.content else {
                Issue.record("expected a class diagram")
                return
            }
            #expect(config.filter == Selector(explicitIDs: ["A", "B", "C"]))
            #expect(diagram.name == "Cycle: A ↔ B ↔ C")
            #expect(diagram.isNameUserDefined)
            #expect(store.projects.first?.generatedDiagramIDs.contains(id!) == true)
        }
    }

    @Test func modulesScopeCycleOpensAsAPackageDiagramFilteredToItsMembers() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")

            let id = model.diagrams.openCycle(
                to: projectID, codebaseID: UUID(), scope: .modules, members: ["ModuleA", "ModuleB"])

            #expect(id != nil)
            let diagram = store.generatedDiagrams[id!]!
            #expect(diagram.type == .packageDiagram)
            #expect(diagram.packageDiagramFilter == Selector(explicitModules: ["ModuleA", "ModuleB"]))
            #expect(diagram.name == "Cycle: ModuleA ↔ ModuleB")
        }
    }

    @Test func longCycleNameTruncatesAfterThreeMembers() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")

            let id = model.diagrams.openCycle(
                to: projectID, codebaseID: UUID(), scope: .types, members: ["A", "B", "C", "D"])

            #expect(store.generatedDiagrams[id!]?.name == "Cycle: A ↔ B ↔ C…")
        }
    }

    @Test func openCycleOnAMissingProjectIsANoOp() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)

            let id = model.diagrams.openCycle(
                to: UUID(), codebaseID: UUID(), scope: .types, members: ["A"])

            #expect(id == nil)
            #expect(store.generatedDiagrams.isEmpty)
        }
    }
}
