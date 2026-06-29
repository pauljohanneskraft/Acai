import Testing
import UMLDiagram
@testable import UMLDiff

@Suite("Diff: StateDiagramDiff")
struct StateDiagramDiffTests {

    private func diagram(_ transitions: [StateDiagram.Transition]) -> StateDiagram {
        StateDiagram(
            states: [State(id: "A", name: "A"), State(id: "B", name: "B")],
            transitions: transitions)
    }

    private typealias State = StateDiagram.State
    private typealias Transition = StateDiagram.Transition

    @Test func distinguishesParallelTransitionsBetweenSameStates() {
        // Two transitions A→B differing only by event: `x` is removed, `y` is added. They share
        // (from, to) so a renderer must not collapse them — the diff keys on (from, to, event).
        let old = diagram([Transition(from: "A", to: "B", event: "x")])
        let new = diagram([Transition(from: "A", to: "B", event: "y")])
        let diff = StateDiagramDiff(old: old, new: new)

        // The union keeps both transitions so both can be drawn and tinted independently.
        let union = diff.union.transitions
        #expect(union.count == 2)
        #expect(diff.status(of: Transition(from: "A", to: "B", event: "y")) == .added)
        #expect(diff.status(of: Transition(from: "A", to: "B", event: "x")) == .removed)
    }

    @Test func reportsGuardActionChangeOnSameTriggerAsChanged() {
        let old = diagram([Transition(from: "A", to: "B", event: "x", guardCondition: "ready")])
        let new = diagram([Transition(from: "A", to: "B", event: "x", guardCondition: "done")])
        let diff = StateDiagramDiff(old: old, new: new)
        #expect(diff.status(of: new.transitions[0]) == .changed)
    }
}
