/// A canvas's rotor plan, kept across renders and held through a drag, whose stale order is harmless.
@MainActor
final class DiagramRotorPlanCache {
    private var cached: DiagramRotorPlan?
    private var isHeld = false
    private var isStale = false
    private(set) var buildCount = 0

    func plan(building build: () -> DiagramRotorPlan) -> DiagramRotorPlan {
        if let cached { return cached }
        let plan = build()
        cached = plan
        buildCount += 1
        return plan
    }

    func invalidate() {
        if isHeld {
            isStale = true
        } else {
            cached = nil
        }
    }

    func hold() {
        isHeld = true
    }

    /// Whether the plan was dropped, so the canvas has to render again to rebuild it.
    @discardableResult
    func release() -> Bool {
        isHeld = false
        guard isStale else { return false }
        isStale = false
        cached = nil
        return true
    }
}
