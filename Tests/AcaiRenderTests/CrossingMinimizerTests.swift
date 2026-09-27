import Testing
@testable import AcaiRender

@Suite("Crossing Minimizer")
struct CrossingMinimizerTests {

    // A single-node layer can't change under a top-down sweep (there's nothing to reorder it
    // against), so that sweep alone reaching a fixed point says nothing about whether the other
    // direction has too. Regression for a bug where the early exit stopped right there, before the
    // bottom-up sweep ever ran the reorder that would put n1 (connected to n2) ahead of n0 (not).
    @Test("A converged top-down sweep does not skip the bottom-up sweep")
    func stoppingRequiresBothDirectionsToConverge() {
        let layers = [["n0", "n1"], ["n2"]]
        let adjacency: [String: Set<String>] = ["n1": ["n2"], "n2": ["n1"]]
        let result = CrossingMinimizer(adjacency: adjacency).minimize(layers)
        #expect(result == [["n1", "n0"], ["n2"]])
    }

    @Test("A layer with no reference neighbors is left in its existing order")
    func unconnectedLayerIsUnchanged() {
        let layers = [["n0", "n1"], ["n2", "n3"]]
        let result = CrossingMinimizer(adjacency: [:]).minimize(layers)
        #expect(result == layers)
    }

    @Test("A single layer is returned unchanged")
    func singleLayerIsUnchanged() {
        let layers = [["n0", "n1", "n2"]]
        let result = CrossingMinimizer(adjacency: [:]).minimize(layers)
        #expect(result == layers)
    }
}
