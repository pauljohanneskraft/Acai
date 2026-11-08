/// A per-instance seam for proving a configuration model derives its picker lookups from the
/// analysis once, at init, rather than on every access.
///
/// Injected per instance rather than read from a shared counter, so concurrent tests each observe
/// only their own model.
public struct AnalysisWalkObserver: Sendable {
    private let onWalk: @Sendable () -> Void

    public init(_ onWalk: @escaping @Sendable () -> Void) {
        self.onWalk = onWalk
    }

    /// Called once per pass a model makes over the analysis to derive its lookups.
    public func didWalk() {
        onWalk()
    }
}
