import CoreGraphics
import Foundation
import ImageIO

/// Turns a rendered `CGImage` into encoded image data.
public protocol DiagramImageEncoding: Sendable {
    func encode(_ image: CGImage) throws -> Data
}

/// Writes PNG straight from the `CGImage`, without a full-raster `NSBitmapImageRep`/`UIImage` copy.
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
