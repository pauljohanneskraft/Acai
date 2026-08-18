import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

@Suite("QuickOpenController")
@MainActor
struct QuickOpenControllerTests {
    private func makeModel() throws -> (model: ProjectBrowserViewModel, projectID: UUID, codebaseID: UUID) {
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-quickopen-controller-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let store = ProjectStore(baseDir: storeDir)
        let model = ProjectBrowserViewModel(store: store)
        let projectID = model.editing.addProject(title: "Demo", subtitle: "")
        let codebaseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-quickopen-controller-tests-codebase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: codebaseDir, withIntermediateDirectories: true)
        model.editing.addCodebase(to: projectID, name: "Demo", directoryURL: codebaseDir)
        let codebaseID = try #require(store.projects.first?.codebases.first?.id)
        return (model, projectID, codebaseID)
    }

    private func makeEntry(
        kind: QuickOpenEntry.Kind, projectID: UUID, codebaseID: UUID? = nil,
        generatedDiagramID: UUID? = nil, freeformDiagramID: UUID? = nil, reference: CodeElementReference? = nil
    ) -> QuickOpenEntry {
        QuickOpenEntry(
            id: UUID().uuidString, name: "Foo", kind: kind, subtitle: "", projectID: projectID,
            codebaseID: codebaseID, reference: reference,
            generatedDiagramID: generatedDiagramID, freeformDiagramID: freeformDiagramID)
    }

    @Test func projectEntrySelectsTheProject() throws {
        let (model, projectID, _) = try makeModel()
        let controller = QuickOpenController(model: model)
        controller.apply(nil, entry: makeEntry(kind: .project, projectID: projectID))
        #expect(model.selection == .project(projectID))
    }

    @Test func codebaseEntrySelectsTheCodebase() throws {
        let (model, projectID, codebaseID) = try makeModel()
        let controller = QuickOpenController(model: model)
        controller.apply(nil, entry: makeEntry(kind: .codebase, projectID: projectID, codebaseID: codebaseID))
        #expect(model.selection == .codebase(codebaseID))
    }

    @Test func generatedDiagramEntrySelectsTheDiagram() throws {
        let (model, projectID, codebaseID) = try makeModel()
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))
        let controller = QuickOpenController(model: model)
        controller.apply(
            nil, entry: makeEntry(kind: .generatedDiagram, projectID: projectID, generatedDiagramID: diagramID))
        #expect(model.selection == .generatedDiagram(diagramID))
    }

    @Test func existingResolutionSelectsThatDiagram() throws {
        let (model, projectID, codebaseID) = try makeModel()
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))
        let controller = QuickOpenController(model: model)
        let entry = makeEntry(
            kind: .type, projectID: projectID, codebaseID: codebaseID, reference: .type(id: "Foo"))
        controller.apply(
            CodeElementResolution(diagramType: .packageDiagram, target: .existing(diagramID)), entry: entry)
        #expect(model.selection == .generatedDiagram(diagramID))
    }

    @Test func createResolutionAddsAndSelectsANewDiagram() throws {
        let (model, projectID, codebaseID) = try makeModel()
        let before = model.generatedDiagramsForProject(projectID).count
        let controller = QuickOpenController(model: model)
        let entry = makeEntry(
            kind: .type, projectID: projectID, codebaseID: codebaseID, reference: .type(id: "Foo"))
        controller.apply(
            CodeElementResolution(diagramType: .packageDiagram, target: .create(.packageDiagram)), entry: entry)
        #expect(model.generatedDiagramsForProject(projectID).count == before + 1)
        if case .generatedDiagram(let newID) = model.selection {
            #expect(model.generatedDiagramsForProject(projectID).contains { $0.id == newID })
        } else {
            Issue.record("expected .generatedDiagram selection after creating a diagram")
        }
    }

    @Test func filteredIsCaseInsensitiveAndEmptyForAnEmptyQuery() throws {
        let (model, projectID, _) = try makeModel()
        let controller = QuickOpenController(model: model)
        let entries = [
            makeEntry(kind: .module, projectID: projectID),
            QuickOpenEntry(
                id: "b", name: "Bar", kind: .module, subtitle: "", projectID: projectID,
                codebaseID: nil, reference: nil, generatedDiagramID: nil, freeformDiagramID: nil)
        ]
        #expect(controller.filtered(entries, matching: "").isEmpty)
        #expect(controller.filtered(entries, matching: "foo").map(\.name) == ["Foo"])
        #expect(controller.filtered(entries, matching: "FOO").map(\.name) == ["Foo"])
    }
}
