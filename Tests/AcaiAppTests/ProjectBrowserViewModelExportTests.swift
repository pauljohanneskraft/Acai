import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
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

    // MARK: - Image Export

    @Test func exportingAnImageQueuesAPNGNamedAfterTheDiagram() throws {
        let (model, _, _) = makeModel()
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        model.exportImage(named: "My Classes", using: StubImageExporter(result: .success(png)))

        let pending = try #require(model.pendingExport)
        #expect(pending.filename == "My Classes.png")
        #expect(pending.contentType == .png)
        #expect(pending.data == png)
        #expect(model.store.lastError == nil)
    }

    /// A failed render reaches the user through the store's alert rather than silently leaving the
    /// file exporter unarmed.
    @Test func aFailingExporterReportsAnError() throws {
        let (model, _, _) = makeModel()

        model.exportImage(named: "My Classes", using: StubImageExporter(result: .failure(ExportFailure())))

        #expect(model.pendingExport == nil)
        let error = try #require(model.store.lastError)
        #expect(error.message.contains(ExportFailure().localizedDescription))
    }
}

private struct ExportFailure: LocalizedError {
    var errorDescription: String? { "The diagram is too large to render." }
}

@MainActor
private struct StubImageExporter: DiagramImageExporting {
    let result: Result<Data, any Error>

    func exportPNGData(scale: CGFloat) throws -> Data {
        try result.get()
    }
}
