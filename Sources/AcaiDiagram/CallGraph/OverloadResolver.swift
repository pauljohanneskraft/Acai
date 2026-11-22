import AcaiCore

/// Picks the overloads a call site targets by arity, then labels; with no unique match it falls back
/// to every declaration of the name, so a called overload is never reported dead.
struct OverloadResolver: Sendable {
    private let candidates: [Member]

    init(candidates: [Member]) {
        self.candidates = candidates
    }

    func targets(of site: CallSite) -> [Member] {
        guard let labels = site.arguments else { return candidates }
        let accepting = candidates.filter { $0.acceptsArgumentCount(labels.count) }
        guard accepting.count != 1 else { return accepting }
        // A parameter list a parser recorded incompletely (an unrecorded default) can rule out every candidate.
        guard !accepting.isEmpty else { return candidates }
        var remaining = accepting
        // An overload whose parameter count the call matches exactly beats one it only reaches by
        // omitting a defaulted parameter — the way the languages themselves resolve it.
        let exact = remaining.filter { $0.parameters.count == labels.count }
        if !exact.isEmpty { remaining = exact }
        guard remaining.count > 1 else { return remaining }
        let byLabels = remaining.filter { $0.matchesArgumentLabels(labels) }
        return byLabels.count == 1 ? byLabels : remaining
    }
}
