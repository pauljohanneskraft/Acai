import CoreGraphics
import Foundation
import SwiftUI
import UMLCore

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

/// Renders a generated class diagram to a PNG image using SwiftUI's `ImageRenderer` over the
/// shared `DiagramSnapshotView` — the same views the app draws on screen. Two entry points:
/// a headless one that lays the diagram out from a `CodeArtifact` (used by the CLI), and one
/// that takes an already-laid-out diagram (used by the app to capture the live canvas, drags
/// and all).
///
/// Note: headless rendering requires a macOS GUI/window-server session; it is not a
/// headless-CI path.
@MainActor
public enum DiagramImageRenderer {

    /// Uniform space left around the diagram content, in points.
    public static let defaultPadding: CGFloat = 40

    /// Hard ceiling on either output dimension, in pixels. Beyond this, CoreGraphics PNG
    /// encoding starts to fail and the bitmap becomes impractically large, so the effective
    /// scale is reduced to keep large diagrams within bounds.
    public static let maxPixelDimension: CGFloat = 16384

    // MARK: - Headless (CLI)

    /// Builds and lays out the diagram for `artifact` (using estimated node sizes, since no
    /// SwiftUI measurement happens headlessly) and renders it to PNG data.
    public static func renderPNG(
        artifact: CodeArtifact,
        configuration: DiagramConfiguration,
        scale: CGFloat = 2,
        padding: CGFloat = defaultPadding
    ) throws -> Data {
        let model = DiagramLayoutModel(artifact: artifact, configuration: configuration)
        let sizes = nodeSizes(for: model.nodes)
        let positions = model.performLayout(sizes: sizes)
        let boxes = model.groupingBoxes(positions: positions, sizes: sizes)
        return try renderPNG(
            nodes: model.nodes,
            edges: model.edges,
            positions: positions,
            sizes: sizes,
            groupingBoxes: boxes,
            scale: scale,
            padding: padding
        )
    }

    // MARK: - From laid-out data (app WYSIWYG)

    /// Renders an already-laid-out diagram to PNG data. Positions/sizes are in any coordinate
    /// space; they are normalized internally so the content's top-left maps to the origin.
    public static func renderPNG(
        nodes: [GeneratedDiagramNode],
        edges: [GeneratedDiagramEdge],
        positions: [String: CGPoint],
        sizes: [String: CGSize],
        groupingBoxes: [DiagramLayoutModel.GroupingBox],
        scale: CGFloat = 2,
        padding: CGFloat = defaultPadding
    ) throws -> Data {
        let bounds = contentBounds(positions: positions, sizes: sizes, boxes: groupingBoxes)

        // Normalize so the content's top-left sits at the origin.
        let dx = -bounds.minX
        let dy = -bounds.minY
        let normalizedPositions = positions.mapValues { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        let normalizedBoxes = groupingBoxes.map { box in
            DiagramLayoutModel.GroupingBox(
                id: box.id, label: box.label,
                rect: box.rect.offsetBy(dx: dx, dy: dy), depth: box.depth
            )
        }

        let view = DiagramSnapshotView(
            nodes: nodes,
            edges: edges,
            positions: normalizedPositions,
            sizes: sizes,
            groupingBoxes: normalizedBoxes,
            contentSize: CGSize(width: bounds.width, height: bounds.height),
            padding: padding
        )

        // Clamp the scale so neither output dimension exceeds `maxPixelDimension`; large
        // codebases otherwise produce bitmaps CoreGraphics cannot encode.
        let pointSize = max(bounds.width, bounds.height) + padding * 2
        let maxScale = maxPixelDimension / max(pointSize, 1)
        // Floor the *requested* scale to a small positive value (guards against a zero/negative
        // `--scale`), then take the ceiling last so the result can never exceed `maxScale` — even
        // when `maxScale` itself drops below the floor for very large diagrams.
        let requestedScale = max(scale, 0.1)
        let effectiveScale = min(requestedScale, maxScale)

        let renderer = ImageRenderer(content: view)
        renderer.scale = effectiveScale
        guard let cgImage = renderer.cgImage else {
            throw DiagramImageRenderError.renderingFailed
        }
        return try encodePNG(cgImage)
    }

    // MARK: - Node Sizing

    /// Sizes used for headless layout and edge geometry. On AppKit we measure each node's
    /// real rendered size with `NSHostingView.fittingSize` so edges connect exactly to the
    /// drawn boxes (the live app gets this from SwiftUI measurement, which never fires
    /// headlessly); elsewhere — or if a measurement comes back degenerate — we fall back to
    /// the size estimate.
    private static func nodeSizes(for nodes: [GeneratedDiagramNode]) -> [String: CGSize] {
        var result: [String: CGSize] = [:]
        for node in nodes {
            result[node.id] = measuredSize(for: node) ?? DiagramLayoutModel.estimateSize(for: node)
        }
        return result
    }

    private static func measuredSize(for node: GeneratedDiagramNode) -> CGSize? {
        #if canImport(AppKit)
        let host = NSHostingView(rootView: TypeNodeView(node: node, isSelected: false))
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return nil }
        return size
        #else
        return nil
        #endif
    }

    // MARK: - Helpers

    /// The bounding rect of all node rects and grouping boxes. Falls back to a small empty
    /// canvas when there is nothing to draw.
    private static func contentBounds(
        positions: [String: CGPoint],
        sizes: [String: CGSize],
        boxes: [DiagramLayoutModel.GroupingBox]
    ) -> CGRect {
        var rects: [CGRect] = boxes.map(\.rect)
        for (id, pos) in positions {
            let size = sizes[id] ?? CGSize(width: 200, height: 100)
            rects.append(CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2,
                                width: size.width, height: size.height))
        }
        guard let first = rects.first else {
            return CGRect(x: 0, y: 0, width: 200, height: 120)
        }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    private static func encodePNG(_ cgImage: CGImage) throws -> Data {
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
