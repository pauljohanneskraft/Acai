import Foundation
import Testing
import UMLCore
@testable import UMLApp

@Suite("Class diagram delta mode")
@MainActor
struct ClassDiagramDeltaTests {

    private func type(_ name: String) -> TypeDeclaration {
        TypeDeclaration(id: name, name: name, qualifiedName: name, kind: .class,
                        accessLevel: .public,
                        location: SourceLocation(filePath: "Sources/App/\(name).swift", line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration], _ rels: [Relationship]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
                     types: types, relationships: rels)
    }

    @Test func deltaColorsAddedAndRemovedEdgesButNotUnchanged() {
        // old: A→B and A→D ; new: A→B (unchanged) and A→C (added). A→D removed.
        let old = artifact([type("A"), type("B"), type("C"), type("D")], [
            Relationship(kind: .dependency, source: "A", target: "B"),
            Relationship(kind: .dependency, source: "A", target: "D")
        ])
        let new = artifact([type("A"), type("B"), type("C"), type("D")], [
            Relationship(kind: .dependency, source: "A", target: "B"),
            Relationship(kind: .dependency, source: "A", target: "C")
        ])
        let codebase = Codebase(name: "App", directoryPath: "/tmp/app")
        let viewModel = ClassDiagramViewModel(codebase: codebase, artifact: new, comparisonArtifact: old)

        #expect(viewModel.isDeltaMode)
        // The union includes A→B (unchanged), A→C (added), A→D (removed).
        let added = viewModel.edges.first { $0.sourceID == "A" && $0.targetID == "C" }
        let removed = viewModel.edges.first { $0.sourceID == "A" && $0.targetID == "D" }
        let unchanged = viewModel.edges.first { $0.sourceID == "A" && $0.targetID == "B" }
        #expect(added != nil && viewModel.deltaColor(for: added!) != nil)
        #expect(removed != nil && viewModel.deltaColor(for: removed!) != nil)
        #expect(unchanged != nil && viewModel.deltaColor(for: unchanged!) == nil)
    }

    @Test func noComparisonMeansNoDeltaColors() {
        let new = artifact([type("A"), type("B")], [Relationship(kind: .dependency, source: "A", target: "B")])
        let viewModel = ClassDiagramViewModel(codebase: Codebase(name: "App", directoryPath: "/tmp/app"),
                                              artifact: new)
        #expect(!viewModel.isDeltaMode)
        if let edge = viewModel.edges.first {
            #expect(viewModel.deltaColor(for: edge) == nil)
        }
    }
}
