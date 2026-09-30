import Testing
import AcaiCore

@Suite("MetricSummary")
struct MetricSummaryTests {
    @Test func emptyInputHasZeroedFields() {
        let summary = MetricSummary<Int>([], value: Double.init)
        #expect(summary.average == 0)
        #expect(summary.maximum == 0)
        #expect(summary.exemplars.isEmpty)
    }

    @Test func singleMaximumIsTheSoleExemplar() {
        let summary = MetricSummary([1, 5, 3], value: Double.init)
        #expect(summary.maximum == 5)
        #expect(summary.exemplars == [5])
        #expect(summary.average == 3)
    }

    @Test func tiedMaximumNamesEveryExemplar() {
        let summary = MetricSummary([4, 7, 2, 7], value: Double.init)
        #expect(summary.maximum == 7)
        #expect(summary.exemplars == [7, 7])
    }
}
