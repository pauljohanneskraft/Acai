import Foundation
import Testing
@testable import UMLApp
@testable import UMLCore

@Suite("Mermaid Export")
@MainActor
struct MermaidExportTests {

    /// Builds an isolated view model whose store lives in a throwaway temp directory and holds
    /// one codebase with a saved artifact.
    private func makeModel() -> (ProjectBrowserViewModel, UUID) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("uml-mermaid-export-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectStore(baseDir: tempDir)
        let codebaseID = UUID()
        store.projects = [
            Project(
                title: "P", subtitle: "",
                codebases: [Codebase(id: codebaseID, name: "C", directoryPath: tempDir.path)]
            )
        ]
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Widget.swift"]),
            types: [TypeDeclaration(id: "Widget", name: "Widget", qualifiedName: "Widget", kind: .class)]
        )
        store.saveArtifact(artifact, for: codebaseID)
        return (ProjectBrowserViewModel(store: store), codebaseID)
    }

    @Test func generatesMermaidForKnownCodebase() {
        let (model, codebaseID) = makeModel()
        let mermaid = model.generateMermaid(for: codebaseID)
        #expect(mermaid.hasPrefix("classDiagram"))
        #expect(mermaid.contains("Widget"))
    }

    @Test func unknownCodebaseYieldsEmptyClassDiagram() {
        let (model, _) = makeModel()
        let mermaid = model.generateMermaid(for: UUID())
        #expect(mermaid == "classDiagram\n")
    }
}
