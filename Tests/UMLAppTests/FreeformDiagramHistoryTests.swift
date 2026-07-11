import CoreGraphics
import Foundation
import Testing
import UMLCore
@testable import UMLApp

/// Regression tests for the undo/redo history of `FreeformDiagramViewModel`.
///
/// These guard the rule that *only an actual mutation* may change the history:
/// a guard-failing call must not push a no-op checkpoint or clear the redo stack.
/// `save()` is a no-op without a configured `diagramID`, so no store is needed.
@Suite("Freeform Diagram Undo History")
@MainActor
struct FreeformDiagramHistoryTests {

    private func model() -> FreeformDiagramViewModel {
        FreeformDiagramViewModel()
    }

    @Test("A real mutation records an undo checkpoint")
    func mutationRecordsUndo() {
        let vm = model()
        #expect(vm.canUndo == false)
        vm.addNode(kind: .type(.class), name: "A", at: .zero)
        #expect(vm.canUndo == true)
    }

    @Test("Undo then redo move between history stacks")
    func undoRedoRoundTrip() {
        let vm = model()
        vm.addNode(kind: .type(.class), name: "A", at: .zero)
        #expect(vm.nodes.count == 1)

        vm.undo()
        #expect(vm.nodes.isEmpty)
        #expect(vm.canUndo == false)
        #expect(vm.canRedo == true)

        vm.redo()
        #expect(vm.nodes.count == 1)
        #expect(vm.canRedo == false)
    }

    @Test("A guard-failing mutation leaves history untouched and keeps redo")
    func noOpMutationDoesNotTouchHistory() {
        let vm = model()
        vm.addNode(kind: .type(.class), name: "A", at: .zero)
        vm.undo()
        // After undo: nothing to undo, one state to redo.
        #expect(vm.canUndo == false)
        #expect(vm.canRedo == true)

        // Calls whose guards fail on a bogus ID must not record a checkpoint
        // (which would clear the redo stack) nor make undo available.
        let bogus = UUID().uuidString
        vm.moveNodeHigher(bogus)
        vm.members.updateNoteText(bogus, text: "hi")

        #expect(vm.canUndo == false)
        #expect(vm.canRedo == true)
        #expect(vm.nodes.isEmpty)
    }

    @Test("Consecutive edits to one text field coalesce into a single undo step")
    func textEditsCoalesce() {
        let vm = model()
        vm.addNode(kind: .type(.class), name: "A", at: .zero)
        let id = vm.nodes[0].id

        // Simulate per-keystroke updates to the same name field.
        vm.members.updateNodeName(id, name: "Ab")
        vm.members.updateNodeName(id, name: "Abc")
        vm.members.updateNodeName(id, name: "Abcd")
        #expect(vm.nodes[0].name == "Abcd")

        // One undo reverts the whole run of keystrokes back to the pre-edit name.
        vm.undo()
        #expect(vm.nodes[0].name == "A")
        #expect(vm.canUndo == true)

        // The next undo removes the node (the add checkpoint) — i.e. the edits were one step.
        vm.undo()
        #expect(vm.nodes.isEmpty)
    }

    @Test("Cut with an empty selection records no checkpoint and keeps redo")
    func emptyCutDoesNotTouchHistory() {
        let vm = model()
        vm.addNode(kind: .type(.class), name: "A", at: .zero)
        vm.undo()
        #expect(vm.canUndo == false)
        #expect(vm.canRedo == true)

        vm.selectedNodeIDs = []
        vm.clipboard.cutSelection()

        #expect(vm.canUndo == false)
        #expect(vm.canRedo == true)
    }

    @Test("Deleting a multi-node selection is a single undo step")
    func deleteSelectionIsSingleUndo() {
        let vm = model()
        vm.addNode(kind: .type(.class), name: "A", at: .zero)
        vm.addNode(kind: .type(.class), name: "B", at: CGPoint(x: 100, y: 0))
        #expect(vm.nodes.count == 2)

        vm.selectedNodeIDs = Set(vm.nodes.map(\.id))
        vm.deleteSelection()
        #expect(vm.nodes.isEmpty)

        // A single undo restores both nodes.
        vm.undo()
        #expect(vm.nodes.count == 2)
    }
}
