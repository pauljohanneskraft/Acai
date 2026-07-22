import CoreGraphics
import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// "Save as Freeform" for class diagrams (`GeneratedDiagram.convertToFreeform`'s default path):
/// each type becomes a `.type` node and every relationship a matching edge, keyed by type *id* —
/// not name, since two types can share a simple name, and `positions`/`nodePositions` are already
/// id-keyed at every call site (see `ProjectBrowserViewModel+Export.swift`).
@Suite("Class Diagram → Freeform Conversion")
@MainActor
struct ClassFreeformConversionTests {

    private func classDiagram() -> GeneratedDiagram {
        GeneratedDiagram(name: "Classes", content: .classDiagram(.init()), codebaseID: UUID())
    }

    private func type(id: String, name: String) -> TypeDeclaration {
        TypeDeclaration(id: id, name: name, qualifiedName: id, kind: .class, accessLevel: .public)
    }

    @Test("Same-named types with distinct ids stay separate nodes")
    func sameNameDistinctIdsStaySeparate() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift"]),
            types: [
                type(id: "ModuleA.Foo", name: "Foo"),
                type(id: "ModuleB.Foo", name: "Foo")
            ],
            relationships: [
                Relationship(kind: .dependency, source: "ModuleA.Foo", target: "ModuleB.Foo")
            ]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        #expect(freeform.nodes.count == 2)
        #expect(freeform.edges.count == 1)
        let edge = try #require(freeform.edges.first)
        #expect(edge.sourceNodeID != edge.targetNodeID)
        let nodeIDs = Set(freeform.nodes.map(\.id))
        #expect(nodeIDs.contains(edge.sourceNodeID))
        #expect(nodeIDs.contains(edge.targetNodeID))
    }

    @Test("Positions carry over keyed by type id, matching real call sites")
    func positionsCarryOverByID() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [type(id: "ModuleA.Foo", name: "Foo")]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact,
            positions: ["ModuleA.Foo": CGPoint(x: 64, y: 128)],
            scale: 1, offset: .zero
        )

        let node = try #require(freeform.nodes.first)
        #expect(node.positionX == 64)
        #expect(node.positionY == 128)
    }

    @Test("Types sharing an id collapse to one node, first declaration wins")
    func sharedIDCollapsesFirstWins() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .python, filePaths: ["a.py", "b.py"]),
            types: [
                type(id: "Dup", name: "Dup"),
                type(id: "Dup", name: "Dup")
            ],
            relationships: [
                Relationship(kind: .dependency, source: "Dup", target: "Dup")
            ]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        // The self-referencing relationship is dropped (source == target), same as today, but the
        // node collapse itself must still be first-wins rather than losing identity entirely.
        #expect(freeform.nodes.count == 1)
    }

    @Test("A relationship to an unresolved/external endpoint produces no edge")
    func unresolvedEndpointDropsEdge() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [type(id: "ModuleA.Foo", name: "Foo")],
            relationships: [
                Relationship(kind: .dependency, source: "ModuleA.Foo", target: "SomeExternalType")
            ]
        )

        let freeform = classDiagram().convertToFreeform(
            artifact: artifact, positions: [:], scale: 1, offset: .zero
        )

        #expect(freeform.nodes.count == 1)
        #expect(freeform.edges.isEmpty)
    }
}
