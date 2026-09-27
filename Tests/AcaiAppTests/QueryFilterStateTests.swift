import Testing
import AcaiQuality
@testable import AcaiApp

@Suite("Query filter state")
struct QueryFilterStateTests {
    @Test func aFreshFilterIsEmptyAndClearingRestoresThat() {
        var filter = QueryFilterState()
        #expect(filter.isEmpty)

        filter.members.isPublicVar = true
        #expect(!filter.isEmpty)

        filter.clear()
        #expect(filter.isEmpty)
        #expect(filter.members == MemberFilter())
        #expect(filter.selector == Selector())
    }

    /// The two empty states say different things, so "nothing here" has to be told apart from
    /// "nothing matched" — showing "no types match your filters" to someone who never set one is the
    /// bug this guards.
    @Test func anEmptyListMeansNoTypesUntilAFilterIsSet() {
        var filter = QueryFilterState()
        #expect(filter.emptyStateReason(hasAnyType: false) == .codebaseHasNoTypes)
        #expect(filter.emptyStateReason(hasAnyType: true) == .codebaseHasNoTypes)

        filter.members.isPublicVar = true
        #expect(filter.emptyStateReason(hasAnyType: true) == .nothingMatchedTheFilter)
        #expect(filter.emptyStateReason(hasAnyType: false) == .codebaseHasNoTypes)
    }
}
