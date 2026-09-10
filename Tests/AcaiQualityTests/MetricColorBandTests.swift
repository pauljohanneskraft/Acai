import Foundation
import Testing
import AcaiCore
@testable import AcaiQuality

/// `MetricColorBand` powers `acai diagram --color-by`: a fine-to-critical gradient over a metric's
/// value, with thresholds sourced from the rules file. These tests cover the fraction/clamping math
/// directly, and the per-type lookup against real computed metrics (mirroring `SmellBudgetTests`'s
/// fixture style).
@Suite("Quality: metric colour bands")
struct MetricColorBandTests {

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

    // MARK: - readings(for:)

    @Test func readingsInterpolateLinearlyBetweenFineAndCritical() {
        let types = typeMetrics([wideMethodType("Mid", parameters: 5)])
        let band = MetricColorBand(metric: .maxParameters, fine: 0, critical: 10)
        #expect(band.readings(for: types)["Mid"]?.fraction == 0.5)
    }

    @Test func readingsClampAtFineAndCritical() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 20)])
        let band = MetricColorBand(metric: .maxParameters, fine: 2, critical: 8)
        #expect(band.readings(for: types)["Wide"]?.fraction == 1)
    }

    @Test func readingsClampBelowFine() {
        let types = typeMetrics([wideMethodType("Narrow", parameters: 0)])
        let band = MetricColorBand(metric: .maxParameters, fine: 2, critical: 8)
        #expect(band.readings(for: types)["Narrow"]?.fraction == 0)
    }

    @Test func readingsLookUpEachTypeByIDWithItsRawValue() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7), wideMethodType("Narrow", parameters: 1)])
        let band = MetricColorBand(metric: .maxParameters, fine: 0, critical: 10)
        let readings = band.readings(for: types)
        #expect(readings["Wide"]?.value == 7)
        #expect(readings["Narrow"]?.value == 1)
        #expect(readings["Wide"]?.fraction != readings["Narrow"]?.fraction)
    }

    @Test func readingsOmitTypesForAModuleScopedMetric() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7)])
        let band = MetricColorBand(metric: .instability, fine: 0, critical: 1)
        #expect(band.readings(for: types).isEmpty)
    }

    @Test func aZeroSpanBandTreatsEveryValueAsFine() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7)])
        let band = MetricColorBand(metric: .maxParameters, fine: 3, critical: 3)
        #expect(band.readings(for: types)["Wide"]?.fraction == 0)
    }

    // MARK: - Reading.formattedValue

    @Test func formattedValuePrintsWholeNumbersBare() {
        let reading = MetricColorBand.Reading(fraction: 0.5, value: 7)
        #expect(reading.formattedValue == "7")
    }

    @Test func formattedValueRoundsFractionsToTwoDecimalPlaces() {
        let reading = MetricColorBand.Reading(fraction: 0.5, value: 0.8333)
        #expect(reading.formattedValue == "0.83")
    }

    // MARK: - Decoding

    @Test func decodesFineAndCritical() throws {
        let json = """
        {"metric": "fanOut", "fine": 0, "critical": 10}
        """
        let band = try JSONDecoder().decode(MetricColorBand.self, from: Data(json.utf8))
        #expect(band.metric == .fanOut)
        #expect(band.fine == 0)
        #expect(band.critical == 10)
    }

    // MARK: - QualityRules integration

    @Test func qualityRulesDefaultsToNoColorBands() {
        #expect(QualityRules().colorBands.isEmpty)
    }

    @Test func qualityRulesDecodesColorBandsLeniently() throws {
        let rules = try JSONDecoder().decode(QualityRules.self, from: Data("{}".utf8))
        #expect(rules.colorBands.isEmpty)
    }

    @Test func qualityRulesRoundTripsColorBands() throws {
        let original = QualityRules(colorBands: [MetricColorBand(metric: .fanOut, fine: 0, critical: 10)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QualityRules.self, from: data)
        #expect(decoded.colorBands == original.colorBands)
    }
}
