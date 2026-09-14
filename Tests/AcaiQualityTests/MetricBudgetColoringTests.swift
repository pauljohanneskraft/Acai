import Foundation
import Testing
import AcaiCore
@testable import AcaiQuality

/// `MetricBudget.colorReadings(for:)` powers `acai diagram --color-by`: a fine-to-critical gradient
/// over a metric's value, with endpoints taken from the same `budgets` entry that already gates the
/// metric. These tests cover the fraction/clamping math directly, and the per-type lookup against real
/// computed metrics (mirroring `SmellBudgetTests`'s fixture style).
@Suite("Quality: metric budget colouring")
struct MetricBudgetColoringTests {

    private func wideMethodType(_ name: String, parameters: Int) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            members: [
                Member(
                    name: "configure", kind: .method, accessLevel: .public,
                    parameters: (0..<parameters).map { Parameter(internalName: "p\($0)") })
            ],
            location: SourceLocation(filePath: "\(name).swift", line: 1, column: 1))
    }

    private func typeMetrics(_ types: [TypeDeclaration]) -> [CodeMetrics.TypeMetric] {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types).computeMetrics().types
    }

    // MARK: - colorReadings(for:)

    @Test func readingsInterpolateLinearlyBetweenMinAndMax() {
        let types = typeMetrics([wideMethodType("Mid", parameters: 5)])
        let budget = MetricBudget(metric: .maxParameters, max: 10)
        #expect(budget.colorReadings(for: types)?["Mid"]?.fraction == 0.5)
    }

    @Test func readingsUseMinAsTheFineEndpointWhenSet() {
        let types = typeMetrics([wideMethodType("Mid", parameters: 5)])
        let budget = MetricBudget(metric: .maxParameters, max: 8, min: 2)
        #expect(budget.colorReadings(for: types)?["Mid"]?.fraction == 0.5)
    }

    @Test func readingsClampAtMax() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 20)])
        let budget = MetricBudget(metric: .maxParameters, max: 8, min: 2)
        #expect(budget.colorReadings(for: types)?["Wide"]?.fraction == 1)
    }

    @Test func readingsClampBelowMin() {
        let types = typeMetrics([wideMethodType("Narrow", parameters: 0)])
        let budget = MetricBudget(metric: .maxParameters, max: 8, min: 2)
        #expect(budget.colorReadings(for: types)?["Narrow"]?.fraction == 0)
    }

    @Test func readingsLookUpEachTypeByIDWithItsRawValue() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7), wideMethodType("Narrow", parameters: 1)])
        let budget = MetricBudget(metric: .maxParameters, max: 10)
        let readings = budget.colorReadings(for: types)
        #expect(readings?["Wide"]?.value == 7)
        #expect(readings?["Narrow"]?.value == 1)
        #expect(readings?["Wide"]?.fraction != readings?["Narrow"]?.fraction)
    }

    @Test func readingsOmitTypesForAModuleScopedMetric() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7)])
        let budget = MetricBudget(metric: .instability, max: 1)
        #expect(budget.colorReadings(for: types)?.isEmpty == true)
    }

    @Test func aZeroSpanBudgetTreatsEveryValueAsFine() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7)])
        let budget = MetricBudget(metric: .maxParameters, max: 3, min: 3)
        #expect(budget.colorReadings(for: types)?["Wide"]?.fraction == 0)
    }

    @Test func aBudgetWithNoMaxCannotColor() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7)])
        let budget = MetricBudget(metric: .maxParameters, min: 1)
        #expect(budget.colorReadings(for: types) == nil)
    }

    // MARK: - ColorReading.formattedValue

    @Test func formattedValuePrintsWholeNumbersBare() {
        let reading = MetricBudget.ColorReading(fraction: 0.5, value: 7)
        #expect(reading.formattedValue == "7")
    }

    @Test func formattedValueRoundsFractionsToTwoDecimalPlaces() {
        let reading = MetricBudget.ColorReading(fraction: 0.5, value: 0.8333)
        #expect(reading.formattedValue == "0.83")
    }
}
