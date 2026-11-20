import CoreGraphics

/// The ceilings a rendered raster must fit, capping total area as well as each dimension.
public struct RenderSizeLimits: Equatable, Sendable {

    /// Beyond this, CoreGraphics PNG encoding starts to fail.
    public let maxPixelDimension: CGFloat

    /// At 4 bytes per pixel, 64 megapixels is a 256 MB raster before encoding.
    public let maxPixelArea: CGFloat

    /// Floor for a zero or negative requested scale.
    public let minimumScale: CGFloat

    public init(maxPixelDimension: CGFloat, maxPixelArea: CGFloat, minimumScale: CGFloat = 0.1) {
        self.maxPixelDimension = maxPixelDimension
        self.maxPixelArea = maxPixelArea
        self.minimumScale = minimumScale
    }

    public static let standard = RenderSizeLimits(maxPixelDimension: 16384, maxPixelArea: 64_000_000)

    /// The floored requested scale, lowered until `pointSize` fits both ceilings (which win over the floor).
    public func scale(for pointSize: CGSize, requested: CGFloat) -> CGFloat {
        let width = max(pointSize.width, 1)
        let height = max(pointSize.height, 1)
        let dimensionBound = maxPixelDimension / max(width, height)
        let areaBound = (maxPixelArea / (width * height)).squareRoot()
        return min(max(requested, minimumScale), dimensionBound, areaBound)
    }
}
