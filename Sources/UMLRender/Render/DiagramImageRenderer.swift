import CoreGraphics
import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum DiagramImageRenderError: Error {
    /// `ImageRenderer` produced no `CGImage` (e.g. zero-sized content or no window-server access).
    case renderingFailed
    /// The rendered image could not be encoded as PNG.
    case encodingFailed
}

/// The shared PNG-rasterisation engine: it takes an already-laid-out SwiftUI snapshot view and turns
/// it into PNG data, clamping the scale so neither output dimension exceeds `maxPixelDimension`.
///
/// The per-diagram-kind renderers (``ClassImageRenderer``, ``SequenceImageRenderer``,
/// ``StateImageRenderer``, ``PackageImageRenderer``, ``CallGraphImageRenderer``) each build their
/// own layout + snapshot view and hand it here, so this type stays free of any diagram-model
/// knowledge. All use SwiftUI's `ImageRenderer`, which needs a macOS GUI/window-server session
/// (not a headless-CI path).
@MainActor
public struct DiagramImageRenderer {

    public init() {}

    /// Uniform space left around the diagram content, in points.
    public static let defaultPadding: CGFloat = 40

    /// Hard ceiling on either output dimension, in pixels. Beyond this, CoreGraphics PNG
    /// encoding starts to fail and the bitmap becomes impractically large, so the effective
    /// scale is reduced to keep large diagrams within bounds.
    public static let maxPixelDimension: CGFloat = 16384

    /// Renders a snapshot view sized to `contentSize` (plus padding) to PNG, clamping the scale so
    /// neither output dimension exceeds ``maxPixelDimension``. The scale is floored to a small
    /// positive value first (guarding a zero/negative `--scale`), then ceilinged so the result can
    /// never exceed the max even when the max itself drops below the floor for very large diagrams.
    public func render(
        _ view: some View,
        contentSize: CGSize,
        scale: CGFloat,
        padding: CGFloat = defaultPadding
    ) throws -> Data {
        let pointSize = max(contentSize.width, contentSize.height) + padding * 2
        let maxScale = Self.maxPixelDimension / max(pointSize, 1)
        let effectiveScale = min(max(scale, 0.1), maxScale)

        let renderer = ImageRenderer(content: view)
        renderer.scale = effectiveScale
        guard let cgImage = renderer.cgImage else {
            throw DiagramImageRenderError.renderingFailed
        }
        return try encodePNG(cgImage)
    }

    private func encodePNG(_ cgImage: CGImage) throws -> Data {
        #if canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw DiagramImageRenderError.encodingFailed
        }
        return data
        #elseif canImport(UIKit)
        guard let data = UIImage(cgImage: cgImage).pngData() else {
            throw DiagramImageRenderError.encodingFailed
        }
        return data
        #else
        throw DiagramImageRenderError.encodingFailed
        #endif
    }
}
