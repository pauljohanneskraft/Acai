import Foundation
import Testing
@testable import AcaiApp

/// `ProjectCodebaseEditor.addProject` (B52): creating a project should land the user in it
/// immediately, rather than leaving the prior selection in place. Layer 0 — the underlying model
/// change (`addProject` returning the new id) is unit-testable even though the full "sheet
/// dismissal navigates to the new project" journey is Layer 2.
@Suite("Project creation selection")
@MainActor
struct ProjectCreationSelectionTests {

    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-project-creation-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test("addProject returns the id of the project it just created")
    func addProjectReturnsNewID() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)

            let id = model.editing.addProject(title: "Demo", subtitle: "")

            #expect(store.projects.first?.id == id)
        }
    }

    @Test("Setting selection to the newly created project's id, as the call site does, replaces any prior selection")
    func selectionMovesToNewProject() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let oldID = model.editing.addProject(title: "Old", subtitle: "")
            model.selection = .project(oldID)

            let newID = model.editing.addProject(title: "New", subtitle: "")
            model.selection = .project(newID)

            #expect(model.selection == .project(newID))
            #expect(model.selection != .project(oldID))
        }
    }
}
