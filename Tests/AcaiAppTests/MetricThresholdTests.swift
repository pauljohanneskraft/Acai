import Testing
@testable import AcaiApp

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
