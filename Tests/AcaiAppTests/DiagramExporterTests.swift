import Foundation
import Testing
@testable import AcaiApp
@testable import AcaiCore

@Suite("Diagram export via system actions")
@MainActor
struct DiagramExporterTests {
    private func makeIndexedModel() -> (ProjectBrowserViewModel, projectID: UUID, codebaseID: UUID) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-diagram-exporter-tests-\(UUID().uuidString)", isDirectory: true)
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

    @Test func exportingAnUnknownDiagramFailsClearly() {
        let (model, _, _) = makeIndexedModel()
        #expect(throws: ProjectBrowserViewModel.AddressFailure.diagramNotFound) {
            try DiagramExporter(browser: model).exportPNGData(diagramID: UUID())
        }
    }

    @Test func exportingABeforeIndexingCodebaseFailsClearly() throws {
        let (model, projectID, codebaseID) = makeIndexedModel()
        // A codebase whose artifact was dropped after the diagram was created (e.g. relocated).
        model.store.artifacts.removeValue(forKey: codebaseID)
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))

        #expect(throws: DiagramExporter.Failure.codebaseNotIndexed("C")) {
            try DiagramExporter(browser: model).exportPNGData(diagramID: diagramID)
        }
    }

    @Test func exportingAChartOnlyDiagramFailsClearly() throws {
        let (model, projectID, codebaseID) = makeIndexedModel()
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .moduleCoupling))

        #expect(throws: DiagramExporter.Failure.unsupportedDiagramType("Module Coupling")) {
            try DiagramExporter(browser: model).exportPNGData(diagramID: diagramID)
        }
    }

    @Test func exportingAGeneratedDiagramProducesPNGData() throws {
        let (model, projectID, codebaseID) = makeIndexedModel()
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))

        let (filename, data) = try DiagramExporter(browser: model).exportPNGData(diagramID: diagramID)

        #expect(filename == model.generatedDiagram(for: diagramID)?.name)
        #expect(!data.isEmpty)
    }

    @Test func exportingAFreeformDiagramProducesPNGData() throws {
        let (model, projectID, _) = makeIndexedModel()
        let diagramID = try #require(model.freeforms.add(to: projectID, name: "Sketch"))
        var diagram = try #require(model.freeformDiagram(for: diagramID))
        diagram.nodes = [FreeformDiagram.Node(name: "Note", content: .note(text: "hello"))]
        model.freeforms.update(diagramID: diagramID, diagram: diagram)

        let (filename, data) = try DiagramExporter(browser: model).exportPNGData(diagramID: diagramID)

        #expect(filename == "Sketch")
        #expect(!data.isEmpty)
    }
}
