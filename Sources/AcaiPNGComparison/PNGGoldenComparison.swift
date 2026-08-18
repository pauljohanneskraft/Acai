import CoreGraphics
import Foundation
import ImageIO

/// Perceptual PNG-vs-golden comparison shared by every render-snapshot consumer (`AcaiRenderTests`'
/// diagram-image goldens, `AcaiAppTests`' freeform-node-view goldens): downsamples both images to a
/// fixed grayscale grid and reports the fraction of cells whose luminance moved beyond a per-cell
/// tolerance. Pure math, no test framework — each consumer maps ``Outcome`` onto its own
/// `#expect`/`Issue.record` calls and headless-host skip logic.
public struct PNGGoldenComparison: Sendable {
    public enum Outcome: Sendable, Equatable {
        case match
        case drifted(changedCells: Int, totalCells: Int)
        case lfsPointer
        case notAPNG
        case undecodable
    }

    private static let comparisonSide = 256
    private static let perCellDelta = 16

    public var maxChangedFraction: Double

    public init(maxChangedFraction: Double = 5.0e-5) {
        self.maxChangedFraction = maxChangedFraction
    }

    public func isLFSPointer(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8) else { return false }
        return prefix.hasPrefix("version https://git-lfs")
    }

    public func hasPNGMagic(_ data: Data) -> Bool {
        Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47]
    }

    /// Compares `committed` (a checked-in golden) against `rendered` (a fresh re-render).
    public func compare(committed: Data, rendered: Data) -> Outcome {
        if isLFSPointer(committed) { return .lfsPointer }
        guard hasPNGMagic(committed), hasPNGMagic(rendered) else { return .notAPNG }
        guard let a = luminanceGrid(committed), let b = luminanceGrid(rendered) else { return .undecodable }
        let changed = zip(a, b).reduce(0) { abs(Int($1.0) - Int($1.1)) > Self.perCellDelta ? $0 + 1 : $0 }
        let fraction = Double(changed) / Double(a.count)
        return fraction <= maxChangedFraction ? .match : .drifted(changedCells: changed, totalCells: a.count)
    }

    /// Decodes PNG `data` into a `comparisonSide`×`comparisonSide` grayscale luminance grid (0–255),
    /// squashing aspect ratio. Both images being compared share dimensions, so the squash is
    /// consistent. `nil` if the image can't be decoded.
    private func luminanceGrid(_ data: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let side = Self.comparisonSide
        var buffer = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &buffer, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // Opaque white ground so transparent regions read as background, then draw scaled to fill.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }
}
