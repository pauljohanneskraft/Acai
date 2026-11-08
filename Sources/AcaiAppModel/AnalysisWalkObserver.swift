/// Notified on each pass a configuration model makes over the analysis to derive its lookups.
public struct AnalysisWalkObserver: Sendable {
    private let onWalk: @Sendable () -> Void

    public init(_ onWalk: @escaping @Sendable () -> Void) {
        self.onWalk = onWalk
    }

    public func didWalk() {
        onWalk()
    }
}
