import Foundation
import Testing
import AcaiCore
import AcaiRender
@testable import AcaiApp

// Focus is the other way a class diagram narrows what it shows — the selector filter is covered in
// `ClassFreeformConversionTests.swift`. An extension rather than a second suite so the test keeps its
// suite, and so SwiftLint counts this body separately from that file's.
extension ClassFreeformConversionTests {

    /// `A → B → C`, plus `D` unrelated to any of them.
    private func focusArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift", "C.swift", "D.swift"]),
            types: ["A", "B", "C", "D"].map {
                TypeDeclaration(id: $0, name: $0, qualifiedName: $0, kind: .class, accessLevel: .public)
            },
            relationships: [
                Relationship(kind: .dependency, source: "A", target: "B"),
                Relationship(kind: .dependency, source: "B", target: "C")
            ]
        )
    }

    private func focusedDiagram(on rootTypeName: String, maxDepth: Int? = nil) -> GeneratedDiagram {
        var config = ClassDiagramConfiguration()
        config.setFocused(true, rootTypeName: rootTypeName)
        config.focus?.maxDepth = maxDepth
        return GeneratedDiagram(name: "Classes", content: .classDiagram(config), codebaseID: UUID())
    }

    /// The copy holds exactly what the live view had on screen, so the assertion is parity with
    /// `ClassDiagramViewModel`, not a hand-written node list.
    @Test("Focus narrows the copy to the focused subgraph, exactly as the source view shows it")
    func focusNarrowsCopyToFocusedSubgraph() {
        let artifact = focusArtifact()
        let diagram = focusedDiagram(on: "A")

        let freeform = diagram.convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        // The default direction walks dependencies to any depth, so `D` is out and `C` is in.
        #expect(Set(freeform.nodes.map(\.name)) == ["A", "B", "C"])
        #expect(freeform.edges.count == 2)

        let onScreen = ClassDiagramViewModel(
            codebase: Codebase(name: "c", directoryPath: "/tmp"), artifact: artifact,
            configuration: diagram.classConfiguration ?? .init()
        )
        #expect(Set(freeform.nodes.map(\.name)) == Set(onScreen.nodes.map(\.name)))
    }

    @Test("A depth-limited focus copies only as far as the source view walked")
    func depthLimitedFocusStopsAtTheSameDepth() {
        let freeform = focusedDiagram(on: "A", maxDepth: 1).convertToFreeform(
            artifact: focusArtifact(), positions: [:], scale: 1, offset: .zero
        )

        #expect(Set(freeform.nodes.map(\.name)) == ["A", "B"])
        #expect(freeform.edges.count == 1)
    }
}
