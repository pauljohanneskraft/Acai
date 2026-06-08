import CoreGraphics
import Testing
import UMLCore
@testable import UMLApp

@Suite("Sugiyama Layout Engine")
struct SugiyamaLayoutEngineTests {

    // Sizes are varied per node (not uniform) so the test validates that the
    // algorithm keeps groups apart at *any* scale, not just a single fixed one.
    private func node(_ id: String, group: String) -> SugiyamaLayoutEngine.NodeInput {
        let seed = CGFloat(abs(id.hashValue) % 5)
        let size = CGSize(width: 90 + seed * 40, height: 50 + seed * 25)
        return SugiyamaLayoutEngine.NodeInput(id: id, size: size, group: group)
    }

    /// Bounding box of all nodes belonging to `group`.
    private func boundingRect(
        ofGroup group: String,
        nodes: [SugiyamaLayoutEngine.NodeInput],
        positions: [String: CGPoint]
    ) -> CGRect {
        var result: CGRect?
        for n in nodes where n.group == group {
            guard let p = positions[n.id] else { continue }
            let r = CGRect(
                x: p.x - n.size.width / 2, y: p.y - n.size.height / 2,
                width: n.size.width, height: n.size.height
            )
            result = result.map { $0.union(r) } ?? r
        }
        return result ?? .null
    }

    /// Builds N groups, each an intra-group chain, plus cross-group edges — the case
    /// that previously made connected components span products and boxes overlap.
    private func makeGraph(
        groups: [String],
        perGroup: Int
    ) -> (nodes: [SugiyamaLayoutEngine.NodeInput], edges: [SugiyamaLayoutEngine.EdgeInput]) {
        var nodes: [SugiyamaLayoutEngine.NodeInput] = []
        var edges: [SugiyamaLayoutEngine.EdgeInput] = []
        for group in groups {
            let ids = (0..<perGroup).map { "\(group)\($0)" }
            ids.forEach { nodes.append(node($0, group: group)) }
            for i in 0..<(ids.count - 1) {
                edges.append(.init(sourceID: ids[i], targetID: ids[i + 1], kind: .dependency))
            }
        }
        // Cross-group edges connecting otherwise separate products.
        for i in 0..<(groups.count - 1) {
            edges.append(.init(sourceID: "\(groups[i])0", targetID: "\(groups[i + 1])0", kind: .dependency))
        }
        return (nodes, edges)
    }

    @Test func everyNodeIsPositioned() {
        let (nodes, edges) = makeGraph(groups: ["A", "B", "C"], perGroup: 4)
        let result = SugiyamaLayoutEngine().layoutByGroup(nodes: nodes, edges: edges)
        for node in nodes {
            #expect(result.positions[node.id] != nil)
        }
    }

    @Test func nestedGroupsNestWithoutOverlap() {
        // Hierarchical group paths ("A/X", "A/Y", ...): the nodes under *any* path prefix
        // must occupy a region disjoint from a sibling prefix's, at every level.
        let leaves = ["A/X", "A/Y", "B/X", "B/Y"]
        var nodes: [SugiyamaLayoutEngine.NodeInput] = []
        var edges: [SugiyamaLayoutEngine.EdgeInput] = []
        for leaf in leaves {
            let ids = (0..<3).map { "\(leaf)#\($0)" }
            ids.forEach { nodes.append(node($0, group: leaf)) }
            for i in 0..<(ids.count - 1) {
                edges.append(.init(sourceID: ids[i], targetID: ids[i + 1], kind: .dependency))
            }
        }
        edges.append(.init(sourceID: "A/X#0", targetID: "B/Y#0", kind: .dependency))  // cross-tree edge

        let positions = SugiyamaLayoutEngine().layoutByGroup(nodes: nodes, edges: edges).positions

        func bbox(prefix: String) -> CGRect {
            var result: CGRect?
            for n in nodes where (n.group ?? "").hasPrefix(prefix) {
                guard let p = positions[n.id] else { continue }
                let r = CGRect(
                    x: p.x - n.size.width / 2, y: p.y - n.size.height / 2,
                    width: n.size.width, height: n.size.height
                )
                result = result.map { $0.union(r) } ?? r
            }
            return result ?? .null
        }
        // Leaf-level siblings are disjoint.
        for i in 0..<leaves.count {
            for j in (i + 1)..<leaves.count {
                #expect(!bbox(prefix: leaves[i]).intersects(bbox(prefix: leaves[j])))
            }
        }
        // Top-level parents (A vs B) are disjoint — so a box around `A/` won't overlap `B/`.
        #expect(!bbox(prefix: "A/").intersects(bbox(prefix: "B/")))
    }

    @Test func productGroupsDoNotOverlap() {
        let groups = ["A", "B", "C", "D", "E"]
        let (nodes, edges) = makeGraph(groups: groups, perGroup: 5)
        let result = SugiyamaLayoutEngine().layoutByGroup(nodes: nodes, edges: edges)

        let rects = groups.map {
            (name: $0, rect: boundingRect(ofGroup: $0, nodes: nodes, positions: result.positions))
        }
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let (a, b) = (rects[i], rects[j])
                #expect(
                    !a.rect.intersects(b.rect),
                    "Package boxes for \(a.name) and \(b.name) overlap: \(a.rect) vs \(b.rect)"
                )
            }
        }
    }

    @Test func everyPairOfNodesHasSpacingBetweenThem() {
        // The engine keeps nodes at least `horizontalSpacing`/`verticalSpacing` apart;
        // expanding each node rect by a margin and asserting they still don't intersect
        // proves nodes are genuinely spaced, not merely non-overlapping/touching.
        let (nodes, edges) = makeGraph(groups: ["A", "B", "C", "D"], perGroup: 6)
        let result = SugiyamaLayoutEngine().layoutByGroup(nodes: nodes, edges: edges)
        let minGap: CGFloat = 30

        let rects: [(id: String, rect: CGRect)] = nodes.compactMap { node in
            guard let p = result.positions[node.id] else { return nil }
            let r = CGRect(
                x: p.x - node.size.width / 2, y: p.y - node.size.height / 2,
                width: node.size.width, height: node.size.height
            ).insetBy(dx: -minGap / 2, dy: -minGap / 2)
            return (node.id, r)
        }
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                #expect(
                    !rects[i].rect.intersects(rects[j].rect),
                    "Nodes \(rects[i].id) and \(rects[j].id) are closer than \(minGap)pt apart"
                )
            }
        }
    }

    @Test func nodesFromDifferentGroupsNeverOverlap() {
        let (nodes, edges) = makeGraph(groups: ["A", "B", "C", "D"], perGroup: 6)
        let result = SugiyamaLayoutEngine().layoutByGroup(nodes: nodes, edges: edges)

        for outer in nodes {
            for inner in nodes where inner.id != outer.id && inner.group != outer.group {
                guard let pa = result.positions[outer.id], let pb = result.positions[inner.id] else { continue }
                let ra = CGRect(
                    x: pa.x - outer.size.width / 2, y: pa.y - outer.size.height / 2,
                    width: outer.size.width, height: outer.size.height
                )
                let rb = CGRect(
                    x: pb.x - inner.size.width / 2, y: pb.y - inner.size.height / 2,
                    width: inner.size.width, height: inner.size.height
                )
                #expect(!ra.intersects(rb), "Nodes \(outer.id) and \(inner.id) from different groups overlap")
            }
        }
    }
}
