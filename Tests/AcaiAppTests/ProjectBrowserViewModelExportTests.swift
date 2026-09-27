import Foundation
import Testing
import AcaiRender
@testable import AcaiApp
@testable import AcaiCore

@Suite("ProjectBrowserViewModel DOT export & save-as-freeform")
@MainActor
struct ProjectBrowserViewModelExportTests {
    private func widgetArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Widget.swift"]),
            types: [TypeDeclaration(id: "Widget", name: "Widget", qualifiedName: "Widget", kind: .class,
                accessLevel: .public)]
        )
    }

    private func makeModel(artifact: CodeArtifact? = nil) -> (ProjectBrowserViewModel, UUID, UUID) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-export-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectStore(
            baseDir: tempDir, analysisStore: AnalysisStore(directory: tempDir.appendingPathComponent("analysis-store")))
        let projectID = UUID()
        let codebaseID = UUID()
        store.projects = [
            Project(
                id: projectID, title: "P", subtitle: "",
                codebases: [Codebase(id: codebaseID, name: "C", directoryPath: tempDir.path)]
            )
        ]
        store.saveArtifact(artifact ?? widgetArtifact(), for: codebaseID)
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

    @Test func savingAsFreeformDiagramAddsItToTheProjectAndSelectsIt() async throws {
        let (model, projectID, codebaseID) = makeModel()
        let diagramID = try #require(
            model.diagrams.add(to: projectID, codebaseID: codebaseID, content: .packageDiagram))
        let before = model.store.freeformDiagrams.count

        model.saveAsFreeformDiagram(id: diagramID, positions: [:], scale: 1, offset: .zero)
        await model.pendingOpen?.value

        #expect(model.store.freeformDiagrams.count == before + 1)
        guard case .freeformDiagram(let newID) = model.selection else {
            Issue.record("expected .freeformDiagram selection after saving")
            return
        }
        #expect(model.store.projects.first { $0.id == projectID }?.freeformDiagramIDs.contains(newID) == true)
        #expect(model.store.freeformDiagrams[newID] != nil)
    }

    /// "Save as Freeform" copies what the diagram had on screen, so a focused diagram must not
    /// quietly hand back the whole codebase.
    @Test func savingAFocusedDiagramCopiesOnlyTheFocusedTypes() async throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift", "D.swift"]),
            types: ["A", "B", "D"].map {
                TypeDeclaration(id: $0, name: $0, qualifiedName: $0, kind: .class, accessLevel: .public)
            },
            relationships: [Relationship(kind: .dependency, source: "A", target: "B")]
        )
        let (model, projectID, codebaseID) = makeModel(artifact: artifact)
        var configuration = ClassDiagramConfiguration()
        configuration.setFocused(true, rootTypeName: "A")
        let diagramID = try #require(model.diagrams.add(
            to: projectID, codebaseID: codebaseID, content: .classDiagram(configuration)))

        model.saveAsFreeformDiagram(id: diagramID, positions: [:], scale: 1, offset: .zero)
        await model.pendingOpen?.value

        guard case .freeformDiagram(let newID) = model.selection else {
            Issue.record("expected .freeformDiagram selection after saving")
            return
        }
        let freeform = try #require(model.store.freeformDiagrams[newID])
        #expect(Set(freeform.nodes.map(\.name)) == ["A", "B"])
    }
}
