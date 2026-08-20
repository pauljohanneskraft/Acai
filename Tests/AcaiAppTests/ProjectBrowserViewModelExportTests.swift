import Foundation
import Testing
@testable import AcaiApp
@testable import AcaiCore

@Suite("ProjectBrowserViewModel DOT export & save-as-freeform")
@MainActor
struct ProjectBrowserViewModelExportTests {
    private func makeModel() -> (ProjectBrowserViewModel, UUID, UUID) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-export-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectStore(baseDir: tempDir)
        let projectID = UUID()
        let codebaseID = UUID()
        store.projects = [
            Project(
                id: projectID, title: "P", subtitle: "",
                codebases: [Codebase(id: codebaseID, name: "C", directoryPath: tempDir.path)]
            )
        ]
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Widget.swift"]),
            types: [TypeDeclaration(id: "Widget", name: "Widget", qualifiedName: "Widget", kind: .class,
                accessLevel: .public)]
        )
        store.saveArtifact(artifact, for: codebaseID)
        return (ProjectBrowserViewModel(store: store), projectID, codebaseID)
    }

    @Test func generatesDOTForKnownCodebase() {
        let (model, _, codebaseID) = makeModel()
        let dot = model.generateDOT(for: codebaseID)
        #expect(dot.hasPrefix("digraph"))
        #expect(dot.contains("Widget"))
    }

    @Test func unknownCodebaseYieldsEmptyDigraph() {
        let (model, _, _) = makeModel()
        let dot = model.generateDOT(for: UUID())
        #expect(dot == "digraph Acai { }")
    }

    @Test func savingAsFreeformDiagramAddsItToTheProjectAndSelectsIt() throws {
        let (model, projectID, codebaseID) = makeModel()
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))
        let before = model.store.freeformDiagrams.count

        model.saveAsFreeformDiagram(id: diagramID, positions: [:], scale: 1, offset: .zero)

        #expect(model.store.freeformDiagrams.count == before + 1)
        guard case .freeformDiagram(let newID) = model.selection else {
            Issue.record("expected .freeformDiagram selection after saving")
            return
        }
        #expect(model.store.projects.first { $0.id == projectID }?.freeformDiagramIDs.contains(newID) == true)
        #expect(model.store.freeformDiagrams[newID] != nil)
    }
}
