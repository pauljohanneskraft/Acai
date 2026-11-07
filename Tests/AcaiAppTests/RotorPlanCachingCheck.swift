import CoreGraphics
import Testing
@testable import AcaiApp

/// Selection and a drag tick reuse a canvas's cached rotor plan; only committing the drag rebuilds it.
@MainActor
struct RotorPlanCachingCheck<Model: CanvasInteraction> {
    let model: Model
    let plan: (Model) -> DiagramRotorPlan

    func verify(moving id: String, to position: CGPoint, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        let before = plan(model).elements.map(\.id)
        let builds = model.rotorPlanCache.buildCount
        #expect(before.last != id, "the moved element must not already read last", sourceLocation: sourceLocation)

        model.selectNode(id, extending: false)
        model.isMultiSelectActive.toggle()
        model.clearSelection()
        _ = plan(model)
        #expect(model.rotorPlanCache.buildCount == builds, sourceLocation: sourceLocation)

        model.beginLayoutGesture()
        model.moveNode(id, to: position)
        #expect(plan(model).elements.map(\.id) == before, sourceLocation: sourceLocation)
        #expect(model.rotorPlanCache.buildCount == builds, sourceLocation: sourceLocation)

        model.endLayoutGesture()
        #expect(plan(model).elements.last?.id == id, sourceLocation: sourceLocation)
        #expect(model.rotorPlanCache.buildCount == builds + 1, sourceLocation: sourceLocation)
    }
}
