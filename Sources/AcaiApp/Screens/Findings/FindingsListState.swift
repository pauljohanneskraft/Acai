import Foundation

/// The Findings list's filters and ordering: which kinds and codebase are selected, whether
/// suppressed findings are shown, and the baseline that marks them.
struct FindingsListState: Equatable {
    var kinds: Set<Finding.Kind> = Set(Finding.Kind.allCases)
    var codebaseID: UUID?
    var showSuppressed = false
    var baseline = FindingsSuppressionBaseline()

    func isSuppressed(_ finding: Finding) -> Bool {
        baseline.suppressedFindingIDs.contains(finding.id)
    }

    /// Severity first, then the freshest index, then the id so equal rows keep one order.
    func visible(from findings: [Finding]) -> [Finding] {
        findings
            .filter { kinds.contains($0.kind) }
            .filter { codebaseID == nil || $0.codebaseID == codebaseID }
            .filter { showSuppressed || !isSuppressed($0) }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                let leftDate = lhs.indexedAt ?? .distantPast
                let rightDate = rhs.indexedAt ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return lhs.id < rhs.id
            }
    }

    /// `baseline` is loaded data rather than a filter, so clearing the filters leaves it alone.
    var hasActiveFilters: Bool {
        kinds != Set(Finding.Kind.allCases) || codebaseID != nil || showSuppressed
    }

    func clearingFilters() -> FindingsListState {
        var state = self
        state.kinds = Set(Finding.Kind.allCases)
        state.codebaseID = nil
        state.showSuppressed = false
        return state
    }

    func toggling(_ kind: Finding.Kind) -> FindingsListState {
        var state = self
        if !state.kinds.insert(kind).inserted { state.kinds.remove(kind) }
        return state
    }

    func toggling(_ finding: Finding) -> FindingsListState {
        var state = self
        if !state.baseline.suppressedFindingIDs.insert(finding.id).inserted {
            state.baseline.suppressedFindingIDs.remove(finding.id)
        }
        return state
    }
}
