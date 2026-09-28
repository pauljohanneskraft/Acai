import CoreGraphics
import Foundation
import Testing
import AcaiArtifactGenerator
import AcaiCore
import AcaiDiagram
import AcaiRender
@testable import AcaiApp

/// "Save as Freeform" must hand the user the diagram they were looking at, so the converted diagram
/// carries one node per rendered node and one edge per rendered edge — for every artifact, not just
/// the hand-built ones the per-type conversion suites use. A failure reports its seed; replay it with
/// `ArtifactGenerator(seed:)`.
@Suite("Freeform conversion invariants", .timeLimit(.minutes(1)))
@MainActor
struct FreeformConversionInvariantTests {

    @Test("A class diagram converts to one node and one edge per rendered element")
    func classConversionPreservesNodeAndEdgeCounts() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = generatedArtifact(seed: seed)
            var configuration = ClassDiagramConfiguration()
            // `.none`: any other grouping adds container boxes on top of the member nodes, which is
            // its own (separately tested) behaviour rather than a count-preserving conversion.
            configuration.grouping = .none
            let diagram = GeneratedDiagram(
                name: "Classes", content: .classDiagram(configuration), codebaseID: UUID())
            let layout = DiagramLayoutModel(
                artifact: artifact, configuration: configuration,
                languages: artifact.standardLanguageResolver
            )

            let freeform = diagram.convertToFreeform(
                artifact: artifact, positions: [:], scale: 1, offset: .zero)

            #expect(freeform.nodes.count == layout.nodes.count, "node count changed for seed \(seed)")
            #expect(freeform.edges.count == layout.edges.count, "edge count changed for seed \(seed)")
            expectEveryEdgeConnectsItsOwnNodes(freeform, label: "class, seed \(seed)")
        }
    }

    @Test("A package diagram converts to one node and one edge per rendered element")
    func packageConversionPreservesNodeAndEdgeCounts() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = generatedArtifact(seed: seed)
            let diagram = GeneratedDiagram(name: "Packages", content: .packageDiagram, codebaseID: UUID())
            let rendered = PackageDiagramBuilder().build(
                from: artifact.enriched(using: artifact.standardLanguageResolver))

            let freeform = diagram.convertToFreeform(
                artifact: artifact, positions: [:], scale: 1, offset: .zero)

            #expect(freeform.nodes.count == rendered.nodes.count, "node count changed for seed \(seed)")
            #expect(freeform.edges.count == rendered.edges.count, "edge count changed for seed \(seed)")
            expectEveryEdgeConnectsItsOwnNodes(freeform, label: "package, seed \(seed)")
        }
    }

    @Test("A call graph converts to one node and one edge per rendered element")
    func callGraphConversionPreservesNodeAndEdgeCounts() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let artifact = generatedArtifact(seed: seed)
            let diagram = GeneratedDiagram(
                name: "Calls", content: .callGraph(.wholeCodebase), codebaseID: UUID())
            let rendered = CallGraphBuilder(scope: .wholeCodebase).build(from: artifact)

            let freeform = diagram.convertToFreeform(
                artifact: artifact, positions: [:], scale: 1, offset: .zero)

            #expect(freeform.nodes.count == rendered.nodes.count, "node count changed for seed \(seed)")
            #expect(freeform.edges.count == rendered.edges.count, "edge count changed for seed \(seed)")
            expectEveryEdgeConnectsItsOwnNodes(freeform, label: "call graph, seed \(seed)")
        }
    }

    /// The counts alone would still pass if an edge pointed at a node that isn't in the diagram, which
    /// renders as a line to nowhere the user can't select or delete.
    private func expectEveryEdgeConnectsItsOwnNodes(_ diagram: FreeformDiagram, label: String) {
        let nodeIDs = Set(diagram.nodes.map(\.id))
        for edge in diagram.edges {
            #expect(nodeIDs.contains(edge.sourceNodeID), "\(label): edge source is not a node in the diagram")
            #expect(nodeIDs.contains(edge.targetNodeID), "\(label): edge target is not a node in the diagram")
        }
    }

    /// Enriched, as a stored analysis always is: the conversions read `relationships`, which only
    /// carries the inferred structural edges after enrichment.
    private func generatedArtifact(seed: UInt64) -> CodeArtifact {
        let artifact = ArtifactGenerator(seed: seed).makeArtifact()
        return artifact.enriched(using: artifact.standardLanguageResolver)
    }
}
