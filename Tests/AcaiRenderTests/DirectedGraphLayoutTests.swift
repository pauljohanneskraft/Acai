import CoreGraphics
import Testing
@testable import AcaiRender

@Suite("Directed Graph Layout")
struct DirectedGraphLayoutTests {

    /// Keyed by id rather than by position, so reordering the input cannot change a node's box.
    private let boxes: [String: CGSize] = [
        "a": CGSize(width: 100, height: 40),
        "b": CGSize(width: 140, height: 60),
        "c": CGSize(width: 120, height: 50),
        "d": CGSize(width: 160, height: 70)
    ]

    private var chain: [(from: String, to: String)] {
        [("a", "b"), ("b", "c"), ("c", "d")]
    }

    private func layout(
        _ ids: [String],
        edges: [(from: String, to: String)] = [],
        overrides: [String: CGPoint] = [:],
        margin: CGFloat = 0
    ) -> DirectedGraphLayout {
        DirectedGraphLayout(
            nodeSizes: ids.map { (id: $0, size: boxes[$0] ?? CGSize(width: 100, height: 40)) },
            edges: edges,
            positionOverrides: overrides,
            margin: margin)
    }

    @Test("The same graph lays out to the same frames every time")
    func layoutIsDeterministic() {
        let ids = ["a", "b", "c", "d"]
        let first = layout(ids, edges: chain)
        let second = layout(ids, edges: chain)
        #expect(first.framesByID == second.framesByID)
        #expect(first.contentSize == second.contentSize)
        #expect(first.framesByID.count == 4)
    }

    @Test("Reordering the nodes does not move them")
    func layoutIsStableUnderNodeReordering() {
        // A shared layer and same-sized components, so input order has something to reorder.
        let fanIn: [(from: String, to: String)] = [("b", "a"), ("c", "a"), ("d", "a"), ("f", "e"), ("h", "g")]
        let forward = layout(["a", "b", "c", "d", "e", "f", "g", "h"], edges: fanIn)
        let reversed = layout(["h", "g", "f", "e", "d", "c", "b", "a"], edges: fanIn)
        #expect(forward.framesByID.count == 8)
        #expect(reversed.framesByID == forward.framesByID)
        #expect(reversed.contentSize == forward.contentSize)
    }

    @Test("Frames are normalised to the margin and the content size covers them all")
    func framesAreNormalisedToTheMargin() throws {
        let result = layout(["a", "b", "c", "d"], edges: chain, margin: 10)
        let frames = Array(result.framesByID.values)
        #expect(frames.count == 4)
        #expect(frames.map(\.minX).min() == 10)
        #expect(frames.map(\.minY).min() == 10)
        let maxX = try #require(frames.map(\.maxX).max())
        let maxY = try #require(frames.map(\.maxY).max())
        #expect(result.contentSize == CGSize(width: maxX + 10, height: maxY + 10))
        // Each node keeps the box it was given.
        for (id, frame) in result.framesByID {
            #expect(frame.size == boxes[id], "\(id)")
        }
    }

    @Test("A single node sits at the margin in a canvas its own size plus both margins")
    func singleNodeTakesItsOwnBox() {
        let result = layout(["a"], margin: 10)
        #expect(result.framesByID == ["a": CGRect(x: 10, y: 10, width: 100, height: 40)])
        #expect(result.contentSize == CGSize(width: 120, height: 60))
    }

    @Test("An empty graph still has a canvas to draw on")
    func emptyGraphHasAValidCanvas() {
        let result = layout([])
        #expect(result.framesByID.isEmpty)
        #expect(result.contentSize == CGSize(width: 1, height: 1))
    }

    @Test("A position override moves that node, and only that node, relative to the rest")
    func positionOverrideIsHonoured() throws {
        let plain = layout(["a", "b"], edges: [("a", "b")])
        let overridden = layout(["a", "b"], edges: [("a", "b")], overrides: ["b": CGPoint(x: 900, y: 0)])
        let a = try #require(overridden.framesByID["a"])
        let b = try #require(overridden.framesByID["b"])
        let plainB = try #require(plain.framesByID["b"])
        #expect(b.minX > a.maxX)
        #expect(b.minX > plainB.minX)
        #expect(overridden.contentSize.width > plain.contentSize.width)
    }
}
