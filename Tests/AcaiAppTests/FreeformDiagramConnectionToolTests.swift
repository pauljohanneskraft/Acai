import CoreGraphics
import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

/// `FreeformDiagramViewModel.ConnectionTool` / `applyLastUsedConnectionTool()`: the compact
/// bottom bar's quick-add slot repeats whichever relationship/message/transition tool was used
/// most recently, against whatever's currently selected.
@Suite("Freeform Connection Tool")
@MainActor
struct FreeformDiagramConnectionToolTests {

    private func model() -> FreeformDiagramViewModel {
        FreeformDiagramViewModel()
    }

    @Test("Defaults to a plain association, usable once two nodes are selected")
    func defaultsToAssociation() {
        let vm = model()
        #expect(vm.lastUsedConnectionTool == .relationship(.association))

        vm.addNode(kind: .type(.class), name: "A", at: .zero)
        vm.addNode(kind: .type(.class), name: "B", at: CGPoint(x: 100, y: 0))
        vm.selectedNodeIDs = [vm.nodes[0].id, vm.nodes[1].id]
        #expect(vm.canApplyLastUsedConnectionTool)

        vm.applyLastUsedConnectionTool()
        #expect(vm.edges.count == 1)
        #expect(vm.edges[0].kind == .association)
    }

    @Test("A relationship tool is disabled unless exactly two nodes are selected")
    func relationshipDisabledWithoutTwoSelected() {
        let vm = model()
        vm.addNode(kind: .type(.class), name: "A", at: .zero)
        vm.selectedNodeIDs = [vm.nodes[0].id]

        #expect(!vm.canApplyLastUsedConnectionTool)
        vm.applyLastUsedConnectionTool()
        #expect(vm.edges.isEmpty)
    }

    @Test("A message tool applies to one selected lifeline as a self-message")
    func messageToolSelfMessage() {
        let vm = model()
        vm.addNode(kind: .lifeline, name: "L", at: .zero)
        vm.lastUsedConnectionTool = .message(.asynchronous)
        vm.selectedNodeIDs = [vm.nodes[0].id]

        #expect(vm.canApplyLastUsedConnectionTool)
        vm.applyLastUsedConnectionTool()

        #expect(vm.edges.count == 1)
        #expect(vm.edges[0].sourceNodeID == vm.edges[0].targetNodeID)
        #expect(vm.edges[0].messageKind == .asynchronous)
    }

    @Test("A message tool applies to two selected lifelines in selection order")
    func messageToolBetweenTwoLifelines() {
        let vm = model()
        vm.addNode(kind: .lifeline, name: "A", at: .zero)
        vm.addNode(kind: .lifeline, name: "B", at: CGPoint(x: 100, y: 0))
        vm.lastUsedConnectionTool = .message(.synchronous)
        vm.selectNode(vm.nodes[0].id, extending: false)
        vm.selectNode(vm.nodes[1].id, extending: true)

        vm.applyLastUsedConnectionTool()

        #expect(vm.edges.count == 1)
        #expect(vm.edges[0].sourceNodeID == vm.nodes[0].id)
        #expect(vm.edges[0].targetNodeID == vm.nodes[1].id)
    }

    @Test("A transition tool applies to one selected state as a self-transition")
    func transitionToolSelfTransition() {
        let vm = model()
        vm.addNode(kind: .state(.normal), name: "S", at: .zero)
        vm.lastUsedConnectionTool = .transition
        vm.selectedNodeIDs = [vm.nodes[0].id]

        #expect(vm.canApplyLastUsedConnectionTool)
        vm.applyLastUsedConnectionTool()

        #expect(vm.edges.count == 1)
        #expect(vm.edges[0].transition != nil)
        #expect(vm.edges[0].sourceNodeID == vm.edges[0].targetNodeID)
    }
}
