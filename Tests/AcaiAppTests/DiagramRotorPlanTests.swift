import CoreGraphics
import Testing
import AcaiDiff
@testable import AcaiApp

@Suite("Diagram rotor plan")
struct DiagramRotorPlanTests {

    private func element(
        _ id: String, x: CGFloat, y: CGFloat, delta: DeltaStatus? = nil
    ) -> DiagramRotorPlan.Element {
        DiagramRotorPlan.Element(id: id, label: id, delta: delta, center: CGPoint(x: x, y: y))
    }

    @Test("Elements read in rows, top to bottom and leading to trailing")
    func readingOrderFollowsRowsThenColumns() {
        let plan = DiagramRotorPlan(elements: [
            element("bottomRight", x: 400, y: 500),
            element("topRight", x: 400, y: 100),
            element("bottomLeft", x: 10, y: 500),
            element("topLeft", x: 10, y: 100)
        ])

        #expect(plan.elements.map(\.id) == ["topLeft", "topRight", "bottomLeft", "bottomRight"])
    }

    @Test("A row of elements whose centres differ slightly still reads as one row")
    func nearlyAlignedElementsShareARow() {
        let plan = DiagramRotorPlan(
            elements: [
                element("right", x: 300, y: 112),
                element("middle", x: 200, y: 100),
                element("left", x: 100, y: 108),
                element("nextRow", x: 100, y: 240)
            ],
            rowTolerance: 24
        )

        #expect(plan.elements.map(\.id) == ["left", "middle", "right", "nextRow"])
    }

    @Test("An element further down than the tolerance starts a new row")
    func aDistantElementStartsItsOwnRow() {
        let plan = DiagramRotorPlan(
            elements: [element("below", x: 10, y: 140), element("above", x: 500, y: 100)],
            rowTolerance: 24
        )

        #expect(plan.elements.map(\.id) == ["above", "below"])
    }

    @Test("The changed rotor carries only changed elements, in the same reading order")
    func changedKeepsReadingOrder() {
        let plan = DiagramRotorPlan(elements: [
            element("removed", x: 300, y: 100, delta: .removed),
            element("untouched", x: 200, y: 100, delta: .unchanged),
            element("added", x: 100, y: 100, delta: .added),
            element("noComparison", x: 400, y: 100),
            element("edited", x: 500, y: 100, delta: .changed)
        ])

        #expect(plan.changed.map(\.id) == ["added", "removed", "edited"])
    }

    @Test("Sort priority descends in reading order and stays above the default, so nodes lead edges")
    func sortPriorityDescendsAboveTheDefault() {
        let plan = DiagramRotorPlan(elements: [
            element("last", x: 10, y: 500), element("first", x: 10, y: 100), element("middle", x: 200, y: 100)
        ])

        let priorities = plan.elements.map { plan.sortPriority(of: $0.id) }
        #expect(priorities == priorities.sorted(by: >))
        #expect(priorities.allSatisfy { $0 > 0 })
    }

    @Test("An element the plan never saw sorts with the canvas's other decoration")
    func anUnknownElementTakesTheDefaultPriority() {
        let plan = DiagramRotorPlan(elements: [element("known", x: 10, y: 10)])

        #expect(plan.sortPriority(of: "absent") == 0)
    }

    @Test("Two elements at the same point order by id rather than by how they were handed over")
    func coincidentElementsOrderDeterministically() {
        let forward = DiagramRotorPlan(elements: [element("a", x: 10, y: 10), element("b", x: 10, y: 10)])
        let reversed = DiagramRotorPlan(elements: [element("b", x: 10, y: 10), element("a", x: 10, y: 10)])

        #expect(forward.elements.map(\.id) == ["a", "b"])
        #expect(reversed.elements.map(\.id) == ["a", "b"])
    }
}
