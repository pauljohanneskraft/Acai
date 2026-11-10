import CoreGraphics
import Foundation
import SwiftUI

public enum DiagramImageRenderError: Error {
    /// `ImageRenderer` produced no `CGImage` (e.g. zero-sized content or no window-server access).
    case renderingFailed
    case encodingFailed
}

/// The shared PNG-rasterisation engine: takes an already-laid-out SwiftUI snapshot view and turns
/// it into PNG data, lowering the scale so the raster fits ``RenderSizeLimits``. Per-diagram-kind
/// renderers build their own layout + snapshot view and hand it here, so this type stays free of
/// diagram-model knowledge. Uses SwiftUI's `ImageRenderer`, which needs a macOS GUI/window-server
/// session.
@MainActor
public struct DiagramImageRenderer {

    private let encoder: any DiagramImageEncoding
    private let limits: RenderSizeLimits

    public init(
        encoder: any DiagramImageEncoding = PNGImageEncoder(),
        limits: RenderSizeLimits = .standard
    ) {
        self.encoder = encoder
        self.limits = limits
    }

    /// Uniform space left around the diagram content, in points. A pure constant — `nonisolated` so
    /// it can seed default arguments (e.g. ``RenderingContext``) outside the main actor.
    nonisolated public static let defaultPadding: CGFloat = 40

    /// Renders a view sized `contentSize` plus `padding` per side, at the scale ``RenderSizeLimits`` allows.
    public func render(
        _ view: some View,
        contentSize: CGSize,
        scale: CGFloat,
        padding: CGFloat = defaultPadding
    ) throws -> Data {
        let pointSize = CGSize(
            width: contentSize.width + padding * 2,
            height: contentSize.height + padding * 2
        )

        let effectiveScale = limits.scale(for: pointSize, requested: scale)
        // Frees the view graph before encoding rather than whenever a run loop next drains.
        let image: CGImage? = autoreleasepool {
            let renderer = ImageRenderer(content: view)
            renderer.scale = effectiveScale
            return renderer.cgImage
        }
        guard let cgImage = image else {
            throw DiagramImageRenderError.renderingFailed
        }
        return try encoder.encode(cgImage)
    }
}
