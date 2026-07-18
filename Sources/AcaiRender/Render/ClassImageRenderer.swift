import CoreGraphics
import Foundation
import SwiftUI
import AcaiCore
import AcaiDiagram

#if canImport(AppKit)
import AppKit
#endif

/// Renders a class diagram to PNG via the shared `DiagramSnapshotView` — the same views the app
/// draws on screen. Two entry points: a headless one that lays out from a `CodeArtifact` (the CLI),
/// and one that takes an already-laid-out diagram (the app, to capture the live canvas).
@MainActor
public struct ClassImageRenderer {
    private let engine = DiagramImageRenderer()

    public init() {}

    /// Builds and lays out the diagram for `artifact` (using estimated node sizes, since no SwiftUI
    /// measurement happens headlessly) and renders it to PNG data.
    public func renderPNG(
        artifact: CodeArtifact,
        configuration: ClassDiagramConfiguration,
        languages: LanguageConfigurationResolver,
        context: RenderingContext = .default,
        colors: ClassColorOverrides = .plain
    ) throws -> Data {
        let model = DiagramLayoutModel(artifact: artifact, configuration: configuration, languages: languages)
        let sizes = nodeSizes(for: model.nodes)
        let positions = model.performLayout(sizes: sizes)
        let boxes = model.groupingBoxes(positions: positions, sizes: sizes)
        let laidOut = LaidOutDiagram(
            nodes: model.nodes, edges: model.edges, positions: positions, sizes: sizes, groupingBoxes: boxes)
        return try renderPNG(laidOut: laidOut, context: context, colors: colors)
    }

    /// Renders an already-laid-out diagram to PNG. Positions/sizes are in any coordinate space; they
    /// are normalized internally so the content's top-left maps to the origin.
    public func renderPNG(
        laidOut: LaidOutDiagram,
        context: RenderingContext = .default,
        colors: ClassColorOverrides = .plain
    ) throws -> Data {
        let bounds = contentBounds(
            positions: laidOut.positions, sizes: laidOut.sizes, boxes: laidOut.groupingBoxes)

        // Normalize so the content's top-left sits at the origin.
        let dx = -bounds.minX
        let dy = -bounds.minY
        let normalizedPositions = laidOut.positions.mapValues { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        let normalizedBoxes = laidOut.groupingBoxes.map { box in
            DiagramLayoutModel.GroupingBox(
                id: box.id, label: box.label, rect: box.rect.offsetBy(dx: dx, dy: dy), depth: box.depth)
        }

        let view = DiagramSnapshotView(
            nodes: laidOut.nodes, edges: laidOut.edges, positions: normalizedPositions, sizes: laidOut.sizes,
            groupingBoxes: normalizedBoxes,
            contentSize: CGSize(width: bounds.width, height: bounds.height),
            padding: context.padding, palette: context.palette, edgeColor: colors.edge, nodeColor: colors.node)

        return try engine.render(
            view, contentSize: CGSize(width: bounds.width, height: bounds.height),
            scale: context.scale, padding: context.padding)
    }

    // MARK: - Node sizing

    /// Sizes used for headless layout and edge geometry. On AppKit we measure each node's real
    /// rendered size with `NSHostingView.fittingSize` so edges connect exactly to the drawn boxes
    /// (the live app gets this from SwiftUI measurement, which never fires headlessly); elsewhere —
    /// or if a measurement comes back degenerate — we fall back to the size estimate.
    private func nodeSizes(for nodes: [GeneratedDiagramNode]) -> [String: CGSize] {
        var result: [String: CGSize] = [:]
        for node in nodes {
            result[node.id] = measuredSize(for: node) ?? DiagramLayoutModel.estimateSize(for: node)
        }
        return result
    }

    private func measuredSize(for node: GeneratedDiagramNode) -> CGSize? {
        #if canImport(AppKit)
        let host = NSHostingView(rootView: TypeNodeView(node: node, isSelected: false))
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return nil }
        return size
        #else
        return nil
        #endif
    }

    /// The bounding rect of all node rects and grouping boxes. Falls back to a small empty canvas
    /// when there is nothing to draw.
    private func contentBounds(
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
}
