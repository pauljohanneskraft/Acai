import Testing
import AcaiCore
@testable import AcaiRender

@Suite("Layer Assigner")
struct LayerAssignerTests {

    private func assignment(
        of nodeIDs: [String],
        _ inheritance: [(String, String)],
        kind: Relationship.Kind = .inheritance,
        maxNodesPerRow: Int = 5
    ) -> [String: Int] {
        LayerAssigner(
            nodeIDs: nodeIDs,
            edges: inheritance.map { (source: $0.0, target: $0.1, kind: kind) },
            maxNodesPerRow: maxNodesPerRow
        ).assignment()
    }

    @Test("A chain of inheritance descends one layer per hop, the base at the top")
    func hierarchyDescendsFromItsRoot() {
        // In UML the source conforms to / inherits from the target, so the target is the parent.
        #expect(assignment(of: ["A", "B", "C"], [("C", "B"), ("B", "A")]) == ["A": 0, "B": 1, "C": 2])
    }

    @Test("A cycle in the hierarchy terminates and still assigns every node")
    func cyclesTerminate() {
        // B and C inherit from each other, below a genuine root.
        let layers = assignment(of: ["A", "B", "C"], [("B", "A"), ("C", "B"), ("B", "C")])
        #expect(Set(layers.keys) == ["A", "B", "C"])
        #expect(layers["A"] == 0)
        #expect(layers.values.allSatisfy { $0 >= 0 })
    }

    @Test("A hierarchy that is nothing but a cycle has no root, so every node is placed as unrelated")
    func pureCycleHasNoRoot() {
        let layers = assignment(of: ["A", "B"], [("A", "B"), ("B", "A")])
        #expect(layers == ["A": 0, "B": 0])
    }

    @Test("Nodes with no hierarchy are spread across rows rather than crammed into one layer")
    func unrelatedNodesAreSpreadAcrossRows() {
        let ids = (0..<12).map { "n\($0)" }
        let layers = assignment(of: ids, [], maxNodesPerRow: 5)
        #expect(Set(layers.keys) == Set(ids))
        let counts = Dictionary(grouping: layers.values) { $0 }.mapValues(\.count)
        #expect(counts == [0: 5, 1: 5, 2: 2])
    }

    @Test("Unrelated nodes start below the deepest hierarchy layer")
    func unrelatedNodesSitBelowTheHierarchy() {
        let layers = assignment(of: ["A", "B", "C", "loose"], [("C", "B"), ("B", "A")])
        #expect(layers == ["A": 0, "B": 1, "C": 2, "loose": 3])
    }

    @Test("A relationship that is not a hierarchy kind does not lift anything")
    func nonHierarchyEdgesAreIgnored() {
        #expect(assignment(of: ["A", "B"], [("B", "A")], kind: .dependency) == ["A": 0, "B": 0])
    }

    @Test("An edge pointing outside the node set is ignored rather than inventing a layer for it")
    func edgesToAbsentNodesAreIgnored() {
        #expect(assignment(of: ["A"], [("A", "Elsewhere")]) == ["A": 0])
        #expect(assignment(of: ["A"], [("Elsewhere", "A")]) == ["A": 0])
    }

    @Test("No nodes means no layers")
    func emptyInputYieldsNothing() {
        #expect(assignment(of: [], []).isEmpty)
    }
}
