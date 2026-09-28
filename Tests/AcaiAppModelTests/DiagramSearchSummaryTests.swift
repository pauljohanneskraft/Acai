import Testing
import AcaiAppModel

@Suite("Diagram Search Summary")
struct DiagramSearchSummaryTests {

    @Test func anEmptyQueryReportsNothingAndCannotStep() {
        let summary = DiagramSearchSummary(query: "", matchCount: 0)
        #expect(summary.message == nil)
        #expect(!summary.canStep)
    }

    /// The bar stays silent until something was actually typed, even while the view model still
    /// reports stale matches from the query before it.
    @Test func anEmptyQueryReportsNothingEvenWithMatchesStillReported() {
        let summary = DiagramSearchSummary(query: "", matchCount: 3)
        #expect(summary.message == nil)
        #expect(summary.canStep)
    }

    @Test func aQueryWithNoMatchesReportsNoMatchesAndCannotStep() {
        let summary = DiagramSearchSummary(query: "nope", matchCount: 0)
        #expect(summary.message == .noMatches)
        #expect(!summary.canStep)
    }

    @Test func aSingleMatchReportsItsCountThroughTheSameMessageAsMany() {
        let one = DiagramSearchSummary(query: "a", matchCount: 1)
        #expect(one.message == .matches(1))
        #expect(one.canStep)

        let many = DiagramSearchSummary(query: "a", matchCount: 3)
        #expect(many.message == .matches(3))
        #expect(many.canStep)
    }
}
