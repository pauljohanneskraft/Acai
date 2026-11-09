import AcaiCore

/// Picks which declaration a call site targets when several share the called name — an overload set.
///
/// A parser records the argument list it can see (``CallSite/arguments``), so the number of
/// arguments a call passes, and the labels it spells, narrow the set: an overload that cannot accept
/// that many arguments is no candidate, and a labelled call only fits parameters carrying those
/// labels. When one candidate survives, it is the target.
///
/// When none does — the parser recorded no argument list, or two overloads stay equally plausible —
/// the call falls back to the *name* and every candidate is reported as a target. That keeps the
/// dead-code scan honest (a called overload is never reported uncalled because the graph guessed a
/// sibling) at the cost of an edge that may be one too many, which the graph's `coverage` caveat
/// already covers.
///
/// A value you instantiate over an overload set and ask for the `targets(of:)` a call site.
struct OverloadResolver: Sendable {
    private let candidates: [Member]

    init(candidates: [Member]) {
        self.candidates = candidates
    }

    func targets(of site: CallSite) -> [Member] {
        guard candidates.count > 1, let labels = site.arguments else { return candidates }
        let byArity = candidates.filter { $0.acceptsArgumentCount(labels.count) }
        guard byArity.count != 1 else { return byArity }
        // No overload accepting this arity means the arity is the unreliable part (a parser that
        // undercounts a trailing closure, a call through a typealias), so it narrows nothing.
        let remaining = byArity.isEmpty ? candidates : byArity
        let byLabels = remaining.filter { $0.matchesArgumentLabels(labels) }
        return byLabels.count == 1 ? byLabels : remaining
    }
}
