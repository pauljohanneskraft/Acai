import CoreGraphics
import Testing
import AcaiArtifactGenerator
import AcaiCore
@testable import AcaiRender

/// The one property a class-diagram layout owes unconditionally: two node rectangles never overlap.
/// Checked over seeded random graphs — a hand-written fixture covers one component shape, and
/// overlap only appears at particular combinations of component count, group nesting and node size.
@Suite("Layout invariants", .timeLimit(.minutes(1)))
struct LayoutInvariantTests {
    private let engine = SugiyamaLayoutEngine()

    @Test("No two node rects overlap")
    func noTwoNodeRectsOverlap() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let graph = LayoutGraph(seed: seed)
            let result = engine.layout(nodes: graph.nodes, edges: graph.edges)
            expectNoOverlap(result, sizes: graph.sizes, label: "seed \(seed)")
        }
    }

    @Test("No two node rects overlap when laid out by group")
    func noTwoNodeRectsOverlapByGroup() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let graph = LayoutGraph(seed: seed)
            let result = engine.layoutByGroup(nodes: graph.nodes, edges: graph.edges)
            expectNoOverlap(result, sizes: graph.sizes, label: "seed \(seed), by group")
        }
    }

    @Test("Every node is placed exactly once")
    func everyNodeIsPlacedExactlyOnce() {
        for seed in ArtifactInvariantSeeds.standard.seeds {
            let graph = LayoutGraph(seed: seed)
            for positions in [
                engine.layout(nodes: graph.nodes, edges: graph.edges).positions,
                engine.layoutByGroup(nodes: graph.nodes, edges: graph.edges).positions
            ] {
                #expect(
                    Set(positions.keys) == Set(graph.nodes.map(\.id)),
                    "a node was dropped or invented for seed \(seed)"
                )
            }
        }
    }

    /// `positions` are node *centres*, so each rect is derived from the centre and the node's own size.
    private func expectNoOverlap(
        _ result: SugiyamaLayoutEngine.LayoutResult, sizes: [String: CGSize], label: String
    ) {
        let rects = result.positions.compactMap { id, centre -> (id: String, rect: CGRect)? in
            guard let size = sizes[id] else { return nil }
            return (
                id,
                CGRect(
                    x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                    width: size.width, height: size.height
                )
            )
        }.sorted { $0.id < $1.id }
        // Otherwise a missing size would silently empty the comparison and pass vacuously.
        #expect(rects.count == result.positions.count, "\(label): a placed node had no size")

        for (outer, first) in rects.enumerated() {
            for second in rects[(outer + 1)...] {
                // `intersects` counts a shared edge as an intersection, which abutting boxes legitimately
                // have; a positive-area overlap is the real defect.
                let overlap = first.rect.intersection(second.rect)
                #expect(
                    overlap.isNull || overlap.width <= 0 || overlap.height <= 0,
                    "\(label): \(first.id) overlaps \(second.id) by \(overlap.width)x\(overlap.height)"
                )
            }
        }
    }
}

/// A seeded layout input derived from a generated artifact: nodes are its types, edges its
/// relationships between two of them, and each node gets a plausible but varying box size.
private struct LayoutGraph {
    let nodes: [SugiyamaLayoutEngine.NodeInput]
    let edges: [SugiyamaLayoutEngine.EdgeInput]
    let sizes: [String: CGSize]

    init(seed: UInt64) {
        let artifact = ArtifactGenerator(seed: seed).makeArtifact()
        var random = SeededGenerator(seed: seed &* 31)
        let types = artifact.flattened()

        var sizes: [String: CGSize] = [:]
        var nodes: [SugiyamaLayoutEngine.NodeInput] = []
        for type in types {
            let size = CGSize(
                width: CGFloat(120 + Int(random.next() % 220)),
                height: CGFloat(60 + Int(random.next() % 180))
            )
            sizes[type.id] = size
            nodes.append(
                SugiyamaLayoutEngine.NodeInput(
                    id: type.id,
                    size: size,
                    // A directory-ish group path, including the "no group" case the layout also has
                    // to place.
                    group: random.next().isMultiple(of: 4)
                        ? nil
                        : "Sources/Group\(random.next() % 3)/Sub\(random.next() % 2)"
                )
            )
        }

        let identifiers = Set(types.map(\.id))
        self.nodes = nodes
        self.sizes = sizes
        self.edges = artifact.relationships
            .filter { identifiers.contains($0.source) && identifiers.contains($0.target) && $0.source != $0.target }
            .map { SugiyamaLayoutEngine.EdgeInput(sourceID: $0.source, targetID: $0.target, kind: $0.kind) }
    }
}
