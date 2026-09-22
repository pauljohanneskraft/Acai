import Testing

@testable import AcaiCore

@Suite("Strongly Connected Components")
struct StronglyConnectedComponentsTests {

    @Test func noEdgesHasNoCycles() {
        let scc = StronglyConnectedComponents(adjacency: ["A": [], "B": []])
        #expect(scc.cycles.isEmpty)
    }

    @Test func acyclicChainHasNoCycles() {
        let scc = StronglyConnectedComponents(adjacency: ["A": ["B"], "B": ["C"], "C": []])
        #expect(scc.cycles.isEmpty)
    }

    @Test func selfLoopIsACycle() {
        let scc = StronglyConnectedComponents(adjacency: ["A": ["A"]])
        #expect(scc.cycles == [["A"]])
    }

    @Test func twoNodeCycle() {
        let scc = StronglyConnectedComponents(adjacency: ["A": ["B"], "B": ["A"]])
        #expect(scc.cycles == [["A", "B"]])
    }

    @Test func threeNodeCycle() {
        let scc = StronglyConnectedComponents(adjacency: ["A": ["B"], "B": ["C"], "C": ["A"]])
        #expect(scc.cycles == [["A", "B", "C"]])
    }

    /// Pins the exact component order Tarjan's algorithm produces (nodes visited in sorted order,
    /// components finished in post-order) so the iterative rewrite can't silently reorder results.
    @Test func multipleCyclesReportInDiscoveryOrder() {
        let adjacency: [String: Set<String>] = [
            "A": ["B"], "B": ["A"],
            "C": ["D"], "D": ["C"],
            "E": []
        ]
        let scc = StronglyConnectedComponents(adjacency: adjacency)
        #expect(scc.cycles == [["A", "B"], ["C", "D"]])
    }

    @Test func cycleWithATailIntoIt() {
        // A -> B -> C -> B: only {B, C} is a cycle, A is not part of it.
        let adjacency: [String: Set<String>] = ["A": ["B"], "B": ["C"], "C": ["B"]]
        let scc = StronglyConnectedComponents(adjacency: adjacency)
        #expect(scc.cycles == [["B", "C"]])
    }

    @Test func nestedCyclesShareANode() {
        // A <-> B, and B <-> C: both pairs collapse into a single SCC through B.
        let adjacency: [String: Set<String>] = ["A": ["B"], "B": ["A", "C"], "C": ["B"]]
        let scc = StronglyConnectedComponents(adjacency: adjacency)
        #expect(scc.cycles == [["A", "B", "C"]])
    }

    /// A deep, purely linear (non-cyclic) chain — the shape that overflows a stack recursing once
    /// per edge, without ever needing to form a cycle to do it.
    @Test func longLinearChainDoesNotOverflowTheStack() {
        let depth = 50_000
        var adjacency: [String: Set<String>] = [:]
        for index in 0..<depth {
            adjacency["N\(index)"] = index + 1 < depth ? ["N\(index + 1)"] : []
        }
        let scc = StronglyConnectedComponents(adjacency: adjacency)
        #expect(scc.cycles.isEmpty)
    }

    /// Same shape as above, but the chain loops back on itself at the far end — the deepest
    /// recursion in Tarjan's algorithm happens while still searching for a cycle, not after
    /// finding one.
    @Test func longChainEndingInACycleDoesNotOverflowTheStack() {
        let depth = 50_000
        var adjacency: [String: Set<String>] = [:]
        for index in 0..<depth {
            adjacency["N\(index)"] = index + 1 < depth ? ["N\(index + 1)"] : ["N0"]
        }
        let scc = StronglyConnectedComponents(adjacency: adjacency)
        #expect(scc.cycles.count == 1)
        #expect(scc.cycles.first?.count == depth)
    }
}
