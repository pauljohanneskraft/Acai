import CoreGraphics
import Foundation
import Testing
import AcaiCore
@testable import AcaiApp

/// Behavioural tests for `FreeformDiagramViewModel`'s canvas operations (move, resize, marquee
/// selection). These pin the behavior that the shared canvas-interaction layer must preserve
/// when the view is refactored onto it — a non-GUI safety net the manual drag check can't give.
@Suite("Freeform Diagram Canvas Operations")
@MainActor
struct FreeformDiagramCanvasTests {

    private func model(withNodesAt points: [CGPoint]) -> FreeformDiagramViewModel {
        let vm = FreeformDiagramViewModel()
        for (i, p) in points.enumerated() {
            vm.addNode(kind: .type(.class), name: "N\(i)", at: p)
        }
        return vm
    }

    @Test("moveNode updates the node position")
    func moveNode() {
        let vm = model(withNodesAt: [.zero])
        let id = vm.nodes[0].id
        vm.moveNode(id, to: CGPoint(x: 120, y: 80))
        #expect(vm.nodePosition(id) == CGPoint(x: 120, y: 80))
    }

    @Test("resizeNode clamps to the minimum size")
    func resizeClampsToMinimum() {
        let vm = model(withNodesAt: [.zero])
        let id = vm.nodes[0].id
        vm.resizeNode(id, width: 10, height: 10)
        let size = vm.nodeSize(id)
        #expect(size.width >= 80)
        #expect(size.height >= 50)
    }

    @Test("selectNodes(in:) selects only nodes whose center is inside the rect")
    func marqueeSelectsByCenter() {
        let vm = model(withNodesAt: [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 200, y: 200),
            CGPoint(x: 50, y: 50)
        ])
        let inside = Set([vm.nodes[0].id, vm.nodes[2].id])
        vm.selectNodes(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(vm.selectedNodeIDs == inside)
    }

    @Test("selectNode replaces or extends the selection")
    func selectNodeExtending() {
        let vm = model(withNodesAt: [.zero, CGPoint(x: 100, y: 0)])
        let a = vm.nodes[0].id
        let b = vm.nodes[1].id
        vm.selectNode(a, extending: false)
        #expect(vm.selectedNodeIDs == [a])
        vm.selectNode(b, extending: true)
        #expect(vm.selectedNodeIDs == [a, b])
        vm.selectNode(b, extending: true)
        #expect(vm.selectedNodeIDs == [a])
    }

    @Test("node ids are stable, collision-free strings")
    func nodeIDsAreUniqueStrings() {
        let vm = model(withNodesAt: [.zero, CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)])
        let ids = vm.nodes.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.isEmpty })
    }

    @Test("Re-pointing a message edge at a non-lifeline demotes it to a relationship")
    func messageEdgeDemotesWhenEndpointLeavesLifelines() {
        let vm = FreeformDiagramViewModel()
        vm.addNode(kind: .lifeline, name: "A", at: .zero)
        vm.addNode(kind: .lifeline, name: "B", at: CGPoint(x: 200, y: 0))
        vm.addNode(kind: .type(.class), name: "C", at: CGPoint(x: 400, y: 0))
        let a = vm.nodes[0].id
        let b = vm.nodes[1].id
        let c = vm.nodes[2].id

        // Edge between two lifelines auto-becomes a message…
        vm.addEdge(from: a, to: b, kind: .dependency)
        let edge = vm.edges[0]
        #expect(vm.sequence.isMessageEdge(edge))
        #expect(vm.sequence.messageEdges.count == 1)

        // …and demotes (in the same model the canvas/inspector read) when re-pointed.
        vm.updateEdge(edge.id, sourceID: a, targetID: c, kind: .dependency)
        let updated = vm.edges[0]
        #expect(!vm.sequence.isMessageEdge(updated))
        #expect(updated.messageOrder == nil)
        #expect(updated.messageKind == nil)
        #expect(vm.sequence.messageEdges.isEmpty)
    }

    @Test("Re-pointing a relationship onto two lifelines promotes it to a message")
    func relationshipPromotesToMessageWhenRepointedBetweenLifelines() {
        let vm = FreeformDiagramViewModel()
        vm.addNode(kind: .lifeline, name: "A", at: .zero)
        vm.addNode(kind: .lifeline, name: "B", at: CGPoint(x: 200, y: 0))
        vm.addNode(kind: .type(.class), name: "C", at: CGPoint(x: 400, y: 0))
        let a = vm.nodes[0].id
        let b = vm.nodes[1].id
        let c = vm.nodes[2].id

        // Starts as a plain relationship (lifeline → type is not a message).
        vm.addEdge(from: a, to: c, kind: .association)
        let edge = vm.edges[0]
        #expect(!vm.sequence.isMessageEdge(edge))
        #expect(edge.messageOrder == nil)

        // Re-pointing the type endpoint onto the second lifeline promotes it to a message.
        vm.updateEdge(edge.id, sourceID: a, targetID: b, kind: .association)
        let updated = vm.edges[0]
        #expect(vm.sequence.isMessageEdge(updated))
        #expect(updated.messageOrder == 1)
        #expect(updated.messageKind == .synchronous)
    }

    @Test("Replacing the node selection clears a selected edge, but extending does not")
    func selectionReplacementClearsSelectedEdge() {
        let vm = model(withNodesAt: [.zero, CGPoint(x: 100, y: 0)])
        let a = vm.nodes[0].id
        let b = vm.nodes[1].id

        // Single click (replace) clears a previously selected edge.
        vm.selectedEdgeID = "edge-1"
        vm.selectNode(a, extending: false)
        #expect(vm.selectedEdgeID == nil)

        // Marquee (replace) clears it too.
        vm.selectedEdgeID = "edge-1"
        vm.selectNodes(in: CGRect(x: -10, y: -10, width: 40, height: 40))
        #expect(vm.selectedEdgeID == nil)

        // Extending the selection leaves the edge selection intact.
        vm.selectedEdgeID = "edge-keep"
        vm.selectNode(b, extending: true)
        #expect(vm.selectedEdgeID == "edge-keep")

        // Clear / select-all also drop it.
        vm.selectedEdgeID = "edge-1"
        vm.clearSelection()
        #expect(vm.selectedEdgeID == nil)
        vm.selectedEdgeID = "edge-1"
        vm.selectAll()
        #expect(vm.selectedEdgeID == nil)
    }
}
