import Foundation
import Testing
import AcaiCore
@testable import AcaiQuality

/// `MetricColorBand` powers `acai diagram --color-by`: a continuous gradient over a metric's value,
/// sourced from the rules file. These tests cover the interpolation/clamping math directly, and the
/// per-type lookup against real computed metrics (mirroring `SmellBudgetTests`'s fixture style).
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

    // MARK: - hex(for:)

    @Test func interpolatesLinearlyBetweenTheBoundingStops() {
        let band = MetricColorBand(metric: .maxParameters, stops: [
            .init(value: 0, color: "#000000"),
            .init(value: 10, color: "#FFFFFF")
        ])
        #expect(band.hex(for: 0) == "#000000")
        #expect(band.hex(for: 10) == "#FFFFFF")
        #expect(band.hex(for: 5) == "#808080")
    }

    @Test func clampsOutsideTheDefinedRangeInsteadOfExtrapolating() {
        let band = MetricColorBand(metric: .maxParameters, stops: [
            .init(value: 2, color: "#111111"),
            .init(value: 8, color: "#EEEEEE")
        ])
        #expect(band.hex(for: -5) == "#111111")
        #expect(band.hex(for: 50) == "#EEEEEE")
    }

    @Test func aSingleStopAppliesToEveryValue() {
        let band = MetricColorBand(metric: .maxParameters, stops: [Stop(value: 3, color: "#123456")])
        #expect(band.hex(for: -100) == "#123456")
        #expect(band.hex(for: 100) == "#123456")
    }

    @Test func sortsStopsRegardlessOfDeclarationOrder() {
        let band = MetricColorBand(metric: .maxParameters, stops: [
            .init(value: 10, color: "#FFFFFF"),
            .init(value: 0, color: "#000000")
        ])
        #expect(band.stops.map(\.value) == [0, 10])
    }

    @Test func hasNoColourWithoutAnyStops() {
        let band = MetricColorBand(metric: .maxParameters, stops: [])
        #expect(band.hex(for: 5) == nil)
    }

    // MARK: - coloring(for:)

    @Test func coloringLooksUpEachTypeByIDWithItsRawValue() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7), wideMethodType("Narrow", parameters: 1)])
        let band = MetricColorBand(metric: .maxParameters, stops: [
            .init(value: 0, color: "#000000"),
            .init(value: 10, color: "#FFFFFF")
        ])
        let coloring = band.coloring(for: types)
        #expect(coloring["Wide"]?.value == 7)
        #expect(coloring["Narrow"]?.value == 1)
        #expect(coloring["Wide"]?.hex != coloring["Narrow"]?.hex)
    }

    @Test func omitsTypesForAModuleScopedMetric() {
        let types = typeMetrics([wideMethodType("Wide", parameters: 7)])
        let band = MetricColorBand(metric: .instability, stops: [Stop(value: 0, color: "#000000")])
        #expect(band.coloring(for: types).isEmpty)
    }

    // MARK: - Coloring.formattedValue

    @Test func formattedValuePrintsWholeNumbersBare() {
        let coloring = MetricColorBand.Coloring(hex: "#000000", value: 7)
        #expect(coloring.formattedValue == "7")
    }

    @Test func formattedValueRoundsFractionsToTwoDecimalPlaces() {
        let coloring = MetricColorBand.Coloring(hex: "#000000", value: 0.8333)
        #expect(coloring.formattedValue == "0.83")
    }

    // MARK: - Decoding

    @Test func decodesAndSortsStops() throws {
        let json = """
        {"metric": "fanOut", "stops": [{"value": 10, "color": "#c62828"}, {"value": 0, "color": "#2e7d32"}]}
        """
        let band = try JSONDecoder().decode(MetricColorBand.self, from: Data(json.utf8))
        #expect(band.metric == .fanOut)
        #expect(band.stops.map(\.value) == [0, 10])
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
        let original = QualityRules(colorBands: [
            MetricColorBand(
                metric: .fanOut,
                stops: [Stop(value: 0, color: "#2e7d32"), Stop(value: 10, color: "#c62828")])
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QualityRules.self, from: data)
        #expect(decoded.colorBands == original.colorBands)
    }
}

private typealias Stop = MetricColorBand.Stop
