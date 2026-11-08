import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AcaiRender

@Suite("Diagram Image Encoder")
struct DiagramImageEncoderTests {

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private func filledImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// `CGImageDestination` writes the image as it stands, so the PNG comes back at exactly the
    /// raster's own pixel size — the `NSBitmapImageRep`/`UIImage` round trip #484 removes copies it
    /// first. Needs no window server, unlike `ImageRenderer`.
    @Test func writesPNGStraightFromTheImageAtItsOwnPixelSize() throws {
        let image = try filledImage(width: 37, height: 19)

        let data = try PNGImageEncoder().encode(image)

        #expect(Array(data.prefix(8)) == Self.pngSignature)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 37)
        #expect(decoded.height == 19)
    }
}
