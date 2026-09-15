import Testing
@testable import AcaiDiagram
@testable import AcaiCore

/// `ClassDiagramOptions.nodeAnnotation` backs `acai diagram --color-by`: a per-node text line so a
/// diagram coloured by measurement never relies on colour alone. Byte-for-byte identical output when
/// unset is covered implicitly by every other test in this target using the default `nil`.
@Suite("Class Diagram Node Annotation")
struct ClassDiagramNodeAnnotationTests {

    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Animal", name: "Animal", qualifiedName: "Animal", kind: .class,
                                 accessLevel: .public)
            ]
        )
    }

    @Test func dotRendererEmitsTheAnnotationUnderTheName() {
        var options = ClassDiagramOptions()
        options.nodeAnnotation = { type in "fanOut: 3 (\(type.name))" }
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact())
        #expect(dot.contains("fanOut: 3 (Animal)"))
    }

    @Test func dotRendererOmitsTheRowWhenAnnotationReturnsNil() {
        var options = ClassDiagramOptions()
        options.nodeAnnotation = { _ in nil }
        let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact())
        #expect(!dot.contains("fanOut"))
    }

    @Test func mermaidRendererAttachesANoteForTheClass() {
        var options = ClassDiagramOptions()
        options.nodeAnnotation = { _ in "fanOut: 3" }
        let mermaid = ClassDiagramMermaidRenderer(options: options).generate(from: artifact())
        #expect(mermaid.contains("note for Animal \"fanOut: 3\""))
    }

    @Test func mermaidRendererSkipsNotesWhenUnset() {
        let mermaid = ClassDiagramMermaidRenderer(options: ClassDiagramOptions()).generate(from: artifact())
        #expect(!mermaid.contains("note for"))
    }
}
