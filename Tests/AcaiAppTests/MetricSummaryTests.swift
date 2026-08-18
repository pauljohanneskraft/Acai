import Testing
@testable import AcaiApp

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

@Suite("MetricThreshold")
struct MetricThresholdTests {
    private let threshold = MetricThreshold(amber: 5, red: 10)

    @Test func belowAmberIsOK() {
        #expect(threshold.severity(for: 4.9) == .ok)
    }

    @Test func atAmberIsCaution() {
        #expect(threshold.severity(for: 5) == .caution)
    }

    @Test func justBelowRedIsStillCaution() {
        #expect(threshold.severity(for: 9.9) == .caution)
    }

    @Test func atRedIsCritical() {
        #expect(threshold.severity(for: 10) == .critical)
    }
}
