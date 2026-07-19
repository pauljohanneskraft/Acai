import Combine
import CoreGraphics
import Testing
@testable import AcaiApp

/// Exercises the shared `CanvasInteraction` / `LayoutBackedCanvas` default implementations against a
/// minimal stub, so the de-duplicated selection / movement / history behavior is verified once,
/// independently of any concrete diagram view model.
@Suite("Canvas Interaction Defaults")
@MainActor
struct CanvasInteractionDefaultsTests {

    /// A fixed-size, layout-backed canvas with hand-placed frames — the smallest possible
    /// `LayoutBackedCanvas` (which refines `CanvasInteraction`).
    @MainActor
    private final class StubCanvas: ObservableObject, LayoutBackedCanvas {
        @Published var positionOverrides: [String: CGPoint] = [:]
        @Published var selectedNodeIDs: Set<String> = []
        @Published var isMultiSelectActive = false
        let history = DiagramHistoryManager<[String: CGPoint]>()
        private let frames: [String: CGRect]

        init(frames: [String: CGRect]) { self.frames = frames }

        var allNodeIDs: [String] { frames.keys.sorted() }
        func nodeFrame(_ id: String) -> CGRect? { frames[id] }
        var defaultNodeSize: CGSize { CGSize(width: 11, height: 22) }
    }

    private func stub() -> StubCanvas {
        StubCanvas(frames: [
            "a": CGRect(x: 0, y: 0, width: 10, height: 20),     // center (5, 10)
            "b": CGRect(x: 100, y: 100, width: 40, height: 60)  // center (120, 130)
        ])
    }

    // MARK: - Selection defaults (CanvasInteraction)

    @Test func selectNodeReplacesExtendsAndToggles() {
        let vm = stub()
        vm.selectNode("a", extending: false)
        #expect(vm.selectedNodeIDs == ["a"])
        vm.selectNode("b", extending: true)
        #expect(vm.selectedNodeIDs == ["a", "b"])
        vm.selectNode("b", extending: true)   // toggle off
        #expect(vm.selectedNodeIDs == ["a"])
        vm.selectNode("b", extending: false)  // replace
        #expect(vm.selectedNodeIDs == ["b"])
    }

    @Test func selectAllSelectsEveryNodeAndClearEmptiesIt() {
        let vm = stub()
        vm.selectAll()
        #expect(vm.selectedNodeIDs == ["a", "b"])
        vm.clearSelection()
        #expect(vm.selectedNodeIDs.isEmpty)
    }

    @Test func marqueeSelectsNodesWhoseCenterIsInsideRect() {
        let vm = stub()
        // Rect around (5, 10) only — picks "a", not "b" at (120, 130).
        vm.selectNodes(in: CGRect(x: -5, y: -5, width: 30, height: 30))
        #expect(vm.selectedNodeIDs == ["a"])
    }

    // MARK: - Layout defaults (LayoutBackedCanvas)

    @Test func nodePositionIsFrameCenter() {
        let vm = stub()
        #expect(vm.nodePosition("a") == CGPoint(x: 5, y: 10))
        #expect(vm.nodePosition("b") == CGPoint(x: 120, y: 130))
        #expect(vm.nodePosition("missing") == nil)
    }

    @Test func moveNodeRecordsOverrideAndResizeIsNoOp() {
        let vm = stub()
        vm.moveNode("a", to: CGPoint(x: 7, y: 8))
        #expect(vm.positionOverrides["a"] == CGPoint(x: 7, y: 8))
        vm.resizeNode("a", width: 999, height: 999)
        #expect(vm.positionOverrides["a"] == CGPoint(x: 7, y: 8))   // unchanged
    }

    @Test func effectiveSizeFallsBackToDefaultWhenUnframed() {
        let vm = stub()
        #expect(vm.effectiveSize(for: "b") == CGSize(width: 40, height: 60))
        #expect(vm.effectiveSize(for: "missing") == CGSize(width: 11, height: 22))
    }

    @Test func historySnapshotMirrorsOverrides() {
        let vm = stub()
        vm.positionOverrides = ["a": CGPoint(x: 1, y: 2)]
        #expect(vm.historySnapshot == ["a": CGPoint(x: 1, y: 2)])
        vm.historySnapshot = ["b": CGPoint(x: 3, y: 4)]
        #expect(vm.positionOverrides == ["b": CGPoint(x: 3, y: 4)])
    }

    @Test func nodeRectIsBuiltFromCenterAndSize() {
        let vm = stub()
        #expect(vm.nodeRect("b") == CGRect(x: 100, y: 100, width: 40, height: 60))
        #expect(vm.nodeRect("missing") == nil)
    }
}
