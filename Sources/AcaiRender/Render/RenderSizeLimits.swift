import CoreGraphics

/// The ceilings a rendered diagram's raster has to fit inside, and the scale that puts it there.
///
/// The area is capped independently of the dimensions rather than inferred from them: a
/// 16,384 × 16,384 bitmap sits inside any per-dimension ceiling and is still a gigabyte of RGBA.
public struct RenderSizeLimits: Equatable, Sendable {

    /// Ceiling on either output dimension, in pixels. Beyond this, CoreGraphics PNG encoding starts
    /// to fail.
    public let maxPixelDimension: CGFloat

    /// Ceiling on the output's total pixel count. At 4 bytes per pixel, 64 megapixels is a 256 MB
    /// raster before encoding.
    public let maxPixelArea: CGFloat

    /// The lowest scale a render falls back to, so a zero or negative `--scale` still draws.
    public let minimumScale: CGFloat

    public init(maxPixelDimension: CGFloat, maxPixelArea: CGFloat, minimumScale: CGFloat = 0.1) {
        self.maxPixelDimension = maxPixelDimension
        self.maxPixelArea = maxPixelArea
        self.minimumScale = minimumScale
    }

    public static let standard = RenderSizeLimits(maxPixelDimension: 16384, maxPixelArea: 64_000_000)

    /// `requested` floored to ``minimumScale`` first, then lowered until `pointSize` rasterises
    /// within both ceilings — so a diagram too large to draw at any useful scale is bounded by the
    /// ceilings rather than by the floor.
    public func scale(for pointSize: CGSize, requested: CGFloat) -> CGFloat {
        let width = max(pointSize.width, 1)
        let height = max(pointSize.height, 1)
        let dimensionBound = maxPixelDimension / max(width, height)
        let areaBound = (maxPixelArea / (width * height)).squareRoot()
        return min(max(requested, minimumScale), dimensionBound, areaBound)
    }
}
