import Testing
@testable import AcaiDiagram

/// `SeverityColors` is the fixed, presentational palette behind `--color-by`: `MetricColorBand`
/// decides the fraction (a codebase concern), this decides the colour (a view concern).
@Suite("Severity colours")
struct SeverityColorsTests {

    @Test func fineIsGreenAndCriticalIsRedByDefault() {
        #expect(SeverityColors.standard.hex(atFraction: 0) == "#2E7D32")
        #expect(SeverityColors.standard.hex(atFraction: 1) == "#C62828")
    }

    @Test func theMidpointIsAmber() {
        #expect(SeverityColors.standard.hex(atFraction: 0.5) == "#F9A825")
    }

    @Test func interpolatesBetweenFineAndMedium() {
        let hex = SeverityColors.standard.hex(atFraction: 0.25)
        #expect(hex != SeverityColors.standard.hex(atFraction: 0))
        #expect(hex != SeverityColors.standard.hex(atFraction: 0.5))
    }

    @Test func clampsOutsideZeroToOneInsteadOfExtrapolating() {
        #expect(SeverityColors.standard.hex(atFraction: -5) == SeverityColors.standard.hex(atFraction: 0))
        #expect(SeverityColors.standard.hex(atFraction: 5) == SeverityColors.standard.hex(atFraction: 1))
    }

    @Test func aCustomPaletteOverridesTheDefaultColours() {
        let palette = SeverityColors(fine: "#000000", medium: "#808080", critical: "#FFFFFF")
        #expect(palette.hex(atFraction: 0) == "#000000")
        #expect(palette.hex(atFraction: 1) == "#FFFFFF")
    }
}
