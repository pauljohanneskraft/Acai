import CoreGraphics
import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// "Save as Freeform" for package diagrams: each build module becomes a `.package` node and every
/// cross-module dependency a dependency edge, so the freeform editor (which renders through the
/// same `ContainerNodeView` the generated view uses) shows an identical module graph.
@Suite("Package Diagram → Freeform Conversion")
@MainActor
struct PackageFreeformConversionTests {

    /// Two modules: `ModuleA` (two concrete classes) depends on `ModuleB` (one protocol) — mirrors
    /// `PackageDiagramTests.twoModuleArtifact()`, the same fixture shape the builder's own tests use.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: [
                "Sources/ModuleA/A.swift", "Sources/ModuleA/A2.swift", "Sources/ModuleB/B.swift"
            ]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleA/A.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "A2", name: "A2", qualifiedName: "A2", kind: .class, accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleA/A2.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .protocol, accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleB/B.swift", line: 1, column: 1)
                )
            ],
            relationships: [
                Relationship(kind: .conformance, source: "A", target: "B"),
                Relationship(kind: .dependency, source: "A2", target: "B")
            ]
        )
    }

    private func packageDiagram() -> GeneratedDiagram {
        GeneratedDiagram(name: "Modules", content: .packageDiagram, codebaseID: UUID())
    }

    @Test("Modules become package nodes")
    func modulesBecomePackageNodes() {
        let freeform = packageDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )
        #expect(freeform.nodes.count == 2)
        #expect(freeform.nodes.allSatisfy { if case .package = $0.content { true } else { false } })
        #expect(Set(freeform.nodes.map(\.name)) == ["ModuleA", "ModuleB"])
    }

    @Test("Cross-module dependency becomes one weighted dependency edge")
    func crossModuleDependencyBecomesEdge() {
        let freeform = packageDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )
        #expect(freeform.edges.count == 1)
        #expect(freeform.edges.allSatisfy { $0.kind == .dependency })
    }

    @Test("A live position carries over keyed by module id (name)")
    func positionsCarryOverByModuleID() throws {
        let freeform = packageDiagram().convertToFreeform(
            artifact: artifact(),
            positions: ["ModuleA": CGPoint(x: 64, y: 128)],
            scale: 1, offset: .zero
        )
        let moduleANode = try #require(freeform.nodes.first { $0.name == "ModuleA" })
        #expect(moduleANode.positionX == 64)
        #expect(moduleANode.positionY == 128)
    }

    @Test("A module with no live/stored position falls back to a staggered stride, not the origin")
    func missingPositionUsesStrideFallback() {
        let freeform = packageDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )
        // `CGPoint: Hashable` needs iOS 18, newer than this package's floor.
        let positions = Set(freeform.nodes.map { [$0.positionX, $0.positionY] })
        #expect(positions.count == 2)
    }

    @Test("An empty package diagram converts to no nodes")
    func emptyPackageDiagramConvertsToNoNodes() {
        let emptyArtifact = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: []))
        let freeform = packageDiagram().convertToFreeform(
            artifact: emptyArtifact, positions: [:], scale: 1, offset: .zero
        )
        #expect(freeform.nodes.isEmpty)
    }
}
