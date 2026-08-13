import Foundation
import Testing
@testable import AcaiApp

@Suite("ProjectBrowserViewModel continuation")
@MainActor
struct ProjectBrowserViewModelContinuationTests {
    private func withTempStoreDir<T>(_ body: (URL) throws -> T) rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-continuation-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    @Test func projectEntrySelectsTheProject() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")

            model.applyQuickOpenEntryDefault(QuickOpenEntry(
                id: "project:\(projectID)", name: "Demo", kind: .project, subtitle: "Project", projectID: projectID
            ))

            #expect(model.selection == .project(projectID))
        }
    }

    @Test func codebaseEntrySelectsTheCodebase() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let codebaseID = UUID()
            model.editing.addCodebase(to: projectID, name: "Demo Codebase", directoryURL: dir)
            let addedID = store.projects.first?.codebases.first?.id ?? codebaseID

            model.applyQuickOpenEntryDefault(QuickOpenEntry(
                id: "codebase:\(addedID)", name: "Demo Codebase", kind: .codebase, subtitle: "Demo",
                projectID: projectID, codebaseID: addedID
            ))

            #expect(model.selection == .codebase(addedID))
        }
    }

    @Test func codebaseEntryWithNoCodebaseIDDoesNothing() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")

            model.applyQuickOpenEntryDefault(QuickOpenEntry(
                id: "codebase:missing", name: "Ghost", kind: .codebase, subtitle: "Demo", projectID: projectID
            ))

            #expect(model.selection == nil)
        }
    }

    @Test func generatedDiagramEntrySelectsTheDiagram() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let codebaseID = UUID()
            let diagramID = model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram)

            model.applyQuickOpenEntryDefault(QuickOpenEntry(
                id: "generatedDiagram:\(diagramID!)", name: "Architecture Overview", kind: .generatedDiagram,
                subtitle: "Demo", projectID: projectID, generatedDiagramID: diagramID
            ))

            #expect(model.selection == .generatedDiagram(diagramID!))
        }
    }

    @Test func freeformDiagramEntrySelectsTheDiagram() {
        withTempStoreDir { dir in
            let store = ProjectStore(baseDir: dir)
            let model = ProjectBrowserViewModel(store: store)
            let projectID = model.editing.addProject(title: "Demo", subtitle: "")
            let diagramID = model.freeforms.add(to: projectID, name: "Sketch")

            model.applyQuickOpenEntryDefault(QuickOpenEntry(
                id: "freeformDiagram:\(diagramID!)", name: "Sketch", kind: .freeformDiagram,
                subtitle: "Demo", projectID: projectID, freeformDiagramID: diagramID
            ))

            #expect(model.selection == .freeformDiagram(diagramID!))
        }
    }
}
