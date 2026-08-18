import CoreGraphics
import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// "Save as Freeform" for package diagrams: each build module becomes a `.package` node and every
/// cross-module dependency a dependency edge, so the freeform editor (which renders through the
/// same `ContainerNodeView` the generated view uses) shows an identical module graph.
///
/// Also covers the opt-in `includeMetricsNote` flag that appends one read-only `.note` node
/// summarizing the coupling metrics (Ca/Ce/I/A/D) that were computed but, before this flag existed,
/// silently dropped on conversion.
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

    private func noteNodes(_ freeform: FreeformDiagram) -> [FreeformDiagram.Node] {
        freeform.nodes.filter { if case .note = $0.content { true } else { false } }
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

    @Test("Default conversion drops the metric note (today's unchanged behavior)")
    func defaultConversionHasNoMetricsNote() {
        let freeform = packageDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero
        )
        #expect(noteNodes(freeform).isEmpty)
    }

    @Test("includeMetricsNote: false explicitly still drops the note")
    func explicitFalseHasNoMetricsNote() {
        let freeform = packageDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero, includeMetricsNote: false
        )
        #expect(noteNodes(freeform).isEmpty)
    }

    @Test("includeMetricsNote: true appends one read-only note summarizing every module's coupling metrics")
    func includeMetricsNoteAppendsSummary() throws {
        let freeform = packageDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero, includeMetricsNote: true
        )
        // Two module nodes plus the appended metrics note.
        #expect(freeform.nodes.count == 3)
        let notes = noteNodes(freeform)
        let note = try #require(notes.first)
        #expect(notes.count == 1)
        // Clearly distinguished as non-editable-derived content per the ticket's requirement, even
        // though `.note` itself doesn't enforce read-only.
        #expect(note.name.lowercased().contains("read-only"))
        guard case .note(let text) = note.content else {
            Issue.record("expected .note content")
            return
        }
        // ModuleA only depends outward (unstable, Ce=2, Ca=0); ModuleB is only depended upon
        // (stable, Ca=2, Ce=0) and fully abstract — same fixture `PackageDiagramTests` asserts on.
        #expect(text.contains("ModuleA"))
        #expect(text.contains("ModuleB"))
        #expect(text.contains("Ca="))
        #expect(text.contains("Ce="))
        #expect(text.contains("I="))
        #expect(text.contains("A="))
        #expect(text.contains("D="))
    }

    @Test("The metrics note doesn't overlap the module nodes it summarizes")
    func metricsNotePositionedClearOfModules() throws {
        let freeform = packageDiagram().convertToFreeform(
            artifact: artifact(), positions: [:], scale: 1, offset: .zero, includeMetricsNote: true
        )
        let note = try #require(noteNodes(freeform).first)
        let moduleMaxY = freeform.nodes
            .filter { if case .package = $0.content { true } else { false } }
            .map(\.positionY)
            .max() ?? 0
        #expect(note.positionY > moduleMaxY)
    }

    @Test("An empty package diagram appends no note even when includeMetricsNote is set")
    func emptyPackageDiagramAppendsNoNote() {
        let emptyArtifact = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: []))
        let freeform = packageDiagram().convertToFreeform(
            artifact: emptyArtifact, positions: [:], scale: 1, offset: .zero, includeMetricsNote: true
        )
        #expect(freeform.nodes.isEmpty)
    }
}
