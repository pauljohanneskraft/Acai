import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// `CycleDiagramData` resolves a `CycleDiagramReference` (as produced by a
/// `cycle`-kind `Violation` — see `CodebaseAnalysesSection.viewAsCycleDiagram`) into exactly that
/// cycle's members and the edges connecting them. No detection logic here — these tests exercise
/// the display-edge resolution and isolation, not cycle-finding itself (that's `CycleFinderTests`'
/// job, unchanged by this pass).
@Suite("Cycle Diagram Data")
struct CycleDiagramDataTests {

    /// A→B→C→A cycle, plus an uninvolved D that depends on A — D must never appear in the isolated
    /// diagram, proving isolation (not just "found some edges").
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift", "C.swift", "D.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    location: .init(filePath: "A.swift", line: 1, column: 1)),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public,
                    location: .init(filePath: "B.swift", line: 1, column: 1)),
                TypeDeclaration(
                    id: "C", name: "C", qualifiedName: "C", kind: .class, accessLevel: .public,
                    location: .init(filePath: "C.swift", line: 1, column: 1)),
                TypeDeclaration(
                    id: "D", name: "D", qualifiedName: "D", kind: .class, accessLevel: .public,
                    location: .init(filePath: "D.swift", line: 1, column: 1))
            ],
            relationships: [
                Relationship(kind: .dependency, source: "A", target: "B"),
                Relationship(kind: .dependency, source: "B", target: "C"),
                Relationship(kind: .dependency, source: "C", target: "A"),
                Relationship(kind: .dependency, source: "D", target: "A")
            ]
        )
    }

    @Test("Isolates exactly the cycle's members — the uninvolved D never appears")
    func isolatesOnlyCycleMembers() {
        let reference = CycleDiagramReference(scope: "types", members: ["A", "B", "C"])
        let data = CycleDiagramData(reference: reference, artifact: artifact())

        #expect(Set(data.nodes.map(\.id)) == ["A", "B", "C"])
        #expect(data.edges.allSatisfy { ["A", "B", "C"].contains($0.from) && ["A", "B", "C"].contains($0.to) })
    }

    @Test("Resolves every edge among the cycle's members")
    func resolvesEveryMemberEdge() {
        let reference = CycleDiagramReference(scope: "types", members: ["A", "B", "C"])
        let data = CycleDiagramData(reference: reference, artifact: artifact())

        let pairs = Set(data.edges.map { "\($0.from)->\($0.to)" })
        #expect(pairs == ["A->B", "B->C", "C->A"])
    }

    @Test("Type-scope nodes use the type's qualified name as their label")
    func typeScopeNodesUseQualifiedName() {
        let reference = CycleDiagramReference(scope: "types", members: ["A"])
        let data = CycleDiagramData(reference: reference, artifact: artifact())
        #expect(data.nodes.first?.label == "A")
    }

    @Test("Module-scope members produce nodes labeled by module name")
    func moduleScopeNodesUseModuleName() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Sources/ModuleA/A.swift", "Sources/ModuleB/B.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleA/A.swift", line: 1, column: 1)),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleB/B.swift", line: 1, column: 1))
            ],
            relationships: [
                Relationship(kind: .dependency, source: "A", target: "B"),
                Relationship(kind: .dependency, source: "B", target: "A")
            ]
        )
        let reference = CycleDiagramReference(scope: "modules", members: ["ModuleA", "ModuleB"])
        let data = CycleDiagramData(reference: reference, artifact: artifact)

        #expect(Set(data.nodes.map(\.id)) == ["ModuleA", "ModuleB"])
        #expect(Set(data.edges.map { "\($0.from)->\($0.to)" }) == ["ModuleA->ModuleB", "ModuleB->ModuleA"])
    }

    @Test("An unresolvable reference (stale/bad scope) still produces its listed members with no edges")
    func staleReferenceProducesNoEdges() {
        let reference = CycleDiagramReference(scope: "types", members: ["Ghost"])
        let data = CycleDiagramData(reference: reference, artifact: artifact())
        #expect(data.nodes.map(\.id) == ["Ghost"])
        #expect(data.edges.isEmpty)
    }
}
