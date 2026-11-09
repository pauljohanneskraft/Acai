import AcaiCore

/// Picks which declaration a call site targets among the ones sharing the called name.
///
/// A parser records the argument list it can see (``CallSite/arguments``), so the number of
/// arguments a call passes, and the labels it spells, narrow the set: a declaration that cannot
/// accept that many arguments is no candidate, and a labelled call only fits parameters carrying
/// those labels. When one candidate survives, it is the target.
///
/// Two outcomes have no single survivor:
/// - **Nothing can accept the call.** Every candidate's parameter list rules the call out, so it
///   targets a declaration this type does not list — a supertype's or an extension's member of the
///   same name. The call is left unresolved rather than attributed to a namesake it cannot be, which
///   is what the graph's `coverage` is for.
/// - **Several stay equally plausible**, or the parser recorded no argument list at all. The call
///   falls back to the *name*: every candidate is reported as a target. That keeps the dead-code
///   scan honest — a called overload is never reported uncalled because the graph picked its
///   sibling — at the cost of an edge that may be one too many. Overloads differing only in
///   parameter *type* land here, since a call site records no argument types.
///
/// A value you instantiate over the same-named declarations and ask for the `targets(of:)` a call.
struct OverloadResolver: Sendable {
    private let candidates: [Member]

    init(candidates: [Member]) {
        self.candidates = candidates
    }

    func targets(of site: CallSite) -> [Member] {
        guard let labels = site.arguments else { return candidates }
        let accepting = candidates.filter { $0.acceptsArgumentCount(labels.count) }
        guard accepting.count != 1 else { return accepting }
        // Nothing of this name can take the call: it reaches an inherited or extension declaration
        // the type does not list, so no namesake here is the target.
        guard !accepting.isEmpty else { return [] }
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
