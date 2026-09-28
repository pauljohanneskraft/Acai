import AcaiQuality

/// What the Query screen is filtering by, and what an empty result means: with no filter set, an empty
/// list means the codebase has no types at all, and with one set it means nothing matched. The two
/// need different empty states, so the distinction is a property of the filter rather than something
/// the view re-derives.
struct QueryFilterState: Equatable {
    var selector = Selector()
    var members = MemberFilter()

    var isEmpty: Bool {
        selector == Selector() && members == MemberFilter()
    }

    mutating func clear() {
        self = QueryFilterState()
    }

    func emptyStateReason(hasAnyType: Bool) -> EmptyStateReason {
        if !hasAnyType { return .codebaseHasNoTypes }
        return isEmpty ? .codebaseHasNoTypes : .nothingMatchedTheFilter
    }

    enum EmptyStateReason: Equatable {
        case codebaseHasNoTypes
        case nothingMatchedTheFilter
    }
}
