import Foundation
import Testing
@testable import UMLApp

/// Unit tests for the generic `DiagramHistoryManager`, focusing on coalescing and reset.
@Suite("Diagram History Manager")
@MainActor
struct DiagramHistoryManagerTests {

    @Test("Consecutive checkpoints with the same coalescing key collapse into one step")
    func sameKeyCoalesces() {
        let history = DiagramHistoryManager<Int>()
        history.checkpoint(0, coalescingKey: "name")
        history.checkpoint(1, coalescingKey: "name")
        history.checkpoint(2, coalescingKey: "name")
        // Only the first (pre-edit) state was recorded; one undo returns to it.
        #expect(history.undo(current: 3) == 0)
        #expect(history.canUndo == false)
    }

    @Test("A different coalescing key starts a new step")
    func differentKeyStartsNewStep() {
        let history = DiagramHistoryManager<Int>()
        history.checkpoint(0, coalescingKey: "a")
        history.checkpoint(1, coalescingKey: "b")
        #expect(history.undo(current: 2) == 1)
        #expect(history.undo(current: 1) == 0)
    }

    @Test("A nil key never coalesces")
    func nilKeyNeverCoalesces() {
        let history = DiagramHistoryManager<Int>()
        history.checkpoint(0)
        history.checkpoint(1)
        #expect(history.undo(current: 2) == 1)
        #expect(history.undo(current: 1) == 0)
    }

    @Test("Undo resets coalescing so a later same-key edit records again")
    func undoResetsCoalescing() {
        let history = DiagramHistoryManager<Int>()
        history.checkpoint(0, coalescingKey: "name")
        _ = history.undo(current: 1)              // restores 0, resets coalescing
        history.checkpoint(5, coalescingKey: "name")  // must record (new group)
        #expect(history.undo(current: 6) == 5)
    }

    @Test("clear empties both stacks")
    func clearEmptiesStacks() {
        let history = DiagramHistoryManager<Int>()
        history.checkpoint(0)
        _ = history.undo(current: 1)
        #expect(history.canRedo == true)
        history.clear()
        #expect(history.canUndo == false)
        #expect(history.canRedo == false)
    }
}
