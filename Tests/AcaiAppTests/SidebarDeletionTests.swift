import Foundation
import Testing
@testable import AcaiApp

@Suite("Sidebar deletion", .timeLimit(.minutes(1)))
@MainActor
struct SidebarDeletionTests {
    private func withModel(_ body: (ProjectStore, ProjectBrowserViewModel) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-sidebar-deletion-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(baseDir: dir)
        try body(store, ProjectBrowserViewModel(store: store))
    }

    @Test func aSelectedProjectAsksToDeleteThatProject() throws {
        try withModel { _, model in
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            model.selection = .project(projectID)

            guard case .project(let project) = model.selectionDeletion else {
                Issue.record("expected a project deletion")
                return
            }
            #expect(project.id == projectID)
            #expect(project.title == "Demo")
        }
    }

    @Test func aSelectedGeneratedDiagramNamesItself() throws {
        try withModel { store, model in
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let added = model.diagrams.add(to: projectID, codebaseID: UUID(), content: .packageDiagram)
            let diagramID = try #require(added)
            let name = try #require(store.generatedDiagrams[diagramID]).name
            model.selection = .generatedDiagram(diagramID)

            guard case .diagram(let deletion) = model.selectionDeletion else {
                Issue.record("expected a diagram deletion")
                return
            }
            #expect(deletion == SidebarDiagramDeletion(diagramID: diagramID, name: name, kind: .generated))
        }
    }

    @Test func confirmingAGeneratedDiagramDeletionRemovesOnlyThatDiagram() throws {
        try withModel { store, model in
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let doomedID = try #require(model.diagrams.add(to: projectID, codebaseID: UUID(), content: .packageDiagram))
            let keptID = try #require(model.diagrams.duplicate(doomedID))
            model.selection = .generatedDiagram(doomedID)
            guard case .diagram(let deletion) = model.selectionDeletion else {
                Issue.record("expected a diagram deletion")
                return
            }

            model.delete(deletion)

            #expect(store.generatedDiagrams[doomedID] == nil)
            #expect(store.generatedDiagrams[keptID] != nil)
        }
    }

    @Test func confirmingAFreeformDiagramDeletionRemovesIt() throws {
        try withModel { store, model in
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let diagramID = try #require(model.freeforms.add(to: projectID, name: "Sketch"))
            model.selection = .freeformDiagram(diagramID)
            guard case .diagram(let deletion) = model.selectionDeletion else {
                Issue.record("expected a diagram deletion")
                return
            }
            #expect(deletion == SidebarDiagramDeletion(diagramID: diagramID, name: "Sketch", kind: .freeform))

            model.delete(deletion)

            #expect(store.freeformDiagrams[diagramID] == nil)
        }
    }

    @Test(arguments: [
        ProjectBrowserViewModel.Selection.repository(URL(fileURLWithPath: "/repos/acai.git")),
        .findings(UUID()),
        .inspect(UUID()),
        .project(UUID()),
        .codebase(UUID()),
        .generatedDiagram(UUID()),
        .freeformDiagram(UUID())
    ])
    func aRowTheSidebarDoesNotOwnOrThatIsGoneHasNothingToDelete(selection: ProjectBrowserViewModel.Selection) {
        withModel { _, model in
            model.selection = selection
            #expect(model.selectionDeletion == nil)
        }
    }

    @Test func noSelectionHasNothingToDelete() {
        withModel { _, model in
            model.selection = nil
            #expect(model.selectionDeletion == nil)
        }
    }
}
