import CoreGraphics
import Testing
@testable import AcaiRender

@Suite("Render Size Limits")
struct RenderSizeLimitsTests {

    private let limits = RenderSizeLimits.standard

    /// Squaring the square-root area bound back can land a few ULPs above the ceiling.
    private let slack: CGFloat = 1.000001

    @Test func keepsTheRequestedScaleForADiagramThatFits() {
        #expect(limits.scale(for: CGSize(width: 1_000, height: 800), requested: 2) == 2)
    }

    @Test func raisesAZeroScaleToTheFloor() {
        #expect(limits.scale(for: CGSize(width: 1_000, height: 800), requested: 0) == limits.minimumScale)
    }

    /// A degenerate content size must not divide by zero or hand back a non-finite scale.
    @Test func survivesAZeroSizedDiagram() {
        #expect(limits.scale(for: .zero, requested: 2) == 2)
    }

    /// swift-nio's 6,832 x 8,192 pt diagram: within the dimension ceiling at scale 2, but 224 megapixels.
    @Test func lowersTheScaleUntilAnOversizedDiagramFitsTheAreaCap() {
        let pointSize = CGSize(width: 6_832, height: 8_192)

        let scale = limits.scale(for: pointSize, requested: 2)
        let pixels = (pointSize.width * scale) * (pointSize.height * scale)

        #expect(scale < 2)
        #expect(pixels <= limits.maxPixelArea * slack)
    }

    /// An elongated diagram hits the dimension ceiling with its area nowhere near the cap.
    @Test func stillCapsEachDimensionWhenTheAreaFits() {
        let pointSize = CGSize(width: 40_000, height: 200)

        let scale = limits.scale(for: pointSize, requested: 1)
        let width = pointSize.width * scale

        #expect(width <= limits.maxPixelDimension * slack)
        #expect(width * (pointSize.height * scale) < limits.maxPixelArea)
    }

    @Test func holdsBothCeilingsForADiagramThatBlowsPastEach() {
        let pointSize = CGSize(width: 60_000, height: 60_000)

        let scale = limits.scale(for: pointSize, requested: 4)
        let width = pointSize.width * scale
        let height = pointSize.height * scale

        #expect(width <= limits.maxPixelDimension * slack)
        #expect(height <= limits.maxPixelDimension * slack)
        #expect(width * height <= limits.maxPixelArea * slack)
    }
}
