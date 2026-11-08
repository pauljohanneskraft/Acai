import CoreGraphics
import Foundation
import ImageIO

/// Turns a rendered `CGImage` into encoded image data. A seam: the rasterisation engine holds one
/// of these rather than encoding inline, so what reaches the encoder is observable.
public protocol DiagramImageEncoding: Sendable {
    func encode(_ image: CGImage) throws -> Data
}

/// Writes PNG straight from the `CGImage`. `NSBitmapImageRep(cgImage:)` and `UIImage.pngData()`
/// each copy the whole raster first, doubling the peak for a large diagram.
public struct PNGImageEncoder: DiagramImageEncoding {

    public init() {}

    public func encode(_ image: CGImage) throws -> Data {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer as CFMutableData, "public.png" as CFString, 1, nil
        ) else {
            throw DiagramImageRenderError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DiagramImageRenderError.encodingFailed
        }
        return buffer as Data
    }
}
