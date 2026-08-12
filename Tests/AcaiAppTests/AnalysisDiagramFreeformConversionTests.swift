import CoreGraphics
import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Module Coupling, Hotspot, and Cycle Diagram are read-only analysis views with no
/// sensible "freeform node" equivalent — see `GeneratedDiagram+Freeform.swift`'s doc comment.
/// `convertToFreeform` handles all three explicitly rather than falling through to the
/// `ClassFreeformConversion` default (which would silently misinterpret their artifact as a class
/// diagram): this locks in that each produces an *empty*, named `FreeformDiagram`, not a class-diagram
/// reinterpretation of whatever artifact happens to be passed.
@Suite("Analysis Diagram (Module Coupling / Hotspot / Cycle) → Freeform Conversion")
@MainActor
struct AnalysisDiagramFreeformConversionTests {

    /// A minimal, non-empty artifact — if any of the three cases fell through to
    /// `ClassFreeformConversion`, this would produce a non-empty node list and fail the assertions
    /// below.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Sources/A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    location: .init(filePath: "Sources/A.swift", line: 1, column: 1)
                )
            ]
        )
    }

    @Test("Module Coupling converts to an empty freeform diagram")
    func moduleCouplingConvertsToEmpty() {
        let diagram = GeneratedDiagram(name: "Coupling", content: .moduleCoupling, codebaseID: UUID())
        let freeform = diagram.convertToFreeform(artifact: artifact(), positions: [:], scale: 1, offset: .zero)
        #expect(freeform.nodes.isEmpty)
        #expect(freeform.edges.isEmpty)
        #expect(freeform.name == "Coupling (Freeform)")
    }

    @Test("Hotspot converts to an empty freeform diagram")
    func hotspotConvertsToEmpty() {
        let diagram = GeneratedDiagram(name: "Hot", content: .hotspot, codebaseID: UUID())
        let freeform = diagram.convertToFreeform(artifact: artifact(), positions: [:], scale: 1, offset: .zero)
        #expect(freeform.nodes.isEmpty)
        #expect(freeform.edges.isEmpty)
    }

    @Test("Cycle Diagram converts to an empty freeform diagram")
    func cycleDiagramConvertsToEmpty() {
        let reference = CycleDiagramReference(scope: "types", members: ["A"])
        let diagram = GeneratedDiagram(name: "Cyc", content: .cycleDiagram(reference), codebaseID: UUID())
        let freeform = diagram.convertToFreeform(artifact: artifact(), positions: [:], scale: 1, offset: .zero)
        #expect(freeform.nodes.isEmpty)
        #expect(freeform.edges.isEmpty)
    }
}
