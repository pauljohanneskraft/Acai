import CoreGraphics
import Testing
@testable import AcaiRender

@Suite("Coordinate Assigner")
struct CoordinateAssignerTests {

    private let horizontalSpacing: CGFloat = 20
    private let verticalSpacing: CGFloat = 30
    private let sizes: [String: CGSize] = [
        "a": CGSize(width: 100, height: 40),
        "b": CGSize(width: 100, height: 40),
        "c": CGSize(width: 120, height: 60)
    ]

    private func assigner(adjacency: [String: Set<String>] = [:]) -> CoordinateAssigner {
        CoordinateAssigner(
            nodeSizes: sizes,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            adjacency: adjacency)
    }

    @Test("Layers stack by their tallest node and each row is centred under the widest")
    func layersStackAndRowsAreCentred() {
        let positions = assigner().assign(layers: [["a", "b"], ["c"]])
        // Row 0 is 220 wide (100 + 20 + 100) and 40 tall; row 1 is 120 wide, so it is inset by 50.
        #expect(positions == [
            "a": CGPoint(x: 50, y: 20),
            "b": CGPoint(x: 170, y: 20),
            "c": CGPoint(x: 110, y: 100)
        ])
    }

    @Test("The same layers produce the same coordinates, refinement passes included")
    func assignmentIsDeterministic() {
        let layers = [["a", "b"], ["c"]]
        let adjacency: [String: Set<String>] = ["a": ["c"], "c": ["a"], "b": ["c"]]
        let first = assigner(adjacency: adjacency).assign(layers: layers)
        let second = assigner(adjacency: adjacency).assign(layers: layers)
        #expect(first == second)
        #expect(first.count == 3)
    }

    @Test("Straightening pulls a node toward its neighbours without letting a row overlap")
    func straighteningPullsNeighboursTogether() throws {
        let layers = [["a", "b"], ["c"]]
        let unconnected = assigner().assign(layers: layers)
        let connected = assigner(adjacency: ["a": ["c"], "c": ["a"]]).assign(layers: layers)

        let gapBefore = abs((unconnected["c"]?.x ?? 0) - (unconnected["a"]?.x ?? 0))
        let gapAfter = abs((connected["c"]?.x ?? 0) - (connected["a"]?.x ?? 0))
        #expect(gapAfter < gapBefore)

        // The row's own nodes still clear each other by at least the horizontal spacing.
        let a = try #require(connected["a"])
        let b = try #require(connected["b"])
        #expect(b.x - a.x >= (100 + 100) / 2 + horizontalSpacing)
    }

    @Test("A node with no recorded size falls back to a default box")
    func unknownSizesFallBack() {
        let positions = assigner().assign(layers: [["ghost"]])
        #expect(positions == ["ghost": CGPoint(x: 90, y: 40)])
    }

    @Test("No layers means no coordinates")
    func emptyLayersYieldNothing() {
        #expect(assigner().assign(layers: []).isEmpty)
        #expect(assigner().assign(layers: [[]]).isEmpty)
    }
}
