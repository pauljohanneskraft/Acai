import CoreGraphics
import Foundation
import SwiftUI
import AcaiDiagram

// Per-diagram-kind PNG renderers. Each builds its own layout model + snapshot view (the same views
// the app canvas draws) and hands it to the shared `DiagramImageRenderer` engine. Split out of the
// former monolithic renderer so each kind is a single-responsibility type and the engine stays
// model-agnostic.

/// Renders a `SequenceDiagram` to PNG. `positionOverrides` (participant-id → horizontal centre)
/// reproduce a hand-spread layout; pass `[:]` for the default arrangement.
@MainActor
public struct SequenceImageRenderer {
    private let engine = DiagramImageRenderer()

    public init() {}

    public func renderPNG(
        sequenceDiagram: SequenceDiagram,
        positionOverrides: [String: CGFloat] = [:],
        context: RenderingContext = .default,
        messageColor: (@Sendable (SequenceLayoutModel.MessageLayout) -> Color?)? = nil
    ) throws -> Data {
        let layout = SequenceLayoutModel(diagram: sequenceDiagram, positionOverrides: positionOverrides)
        let view = SequenceDiagramSnapshotView(
            layout: layout, padding: context.padding, palette: context.palette, messageColor: messageColor)
        return try engine.render(
            view, contentSize: layout.contentSize, scale: context.scale, padding: context.padding)
    }
}

/// Renders a `StateDiagram` to PNG. `positionOverrides` (state-id → centre) reproduce a
/// hand-arranged layout; pass `[:]` for the default arrangement.
@MainActor
public struct StateImageRenderer {
    private let engine = DiagramImageRenderer()

    public init() {}

    public func renderPNG(
        stateDiagram: StateDiagram,
        positionOverrides: [String: CGPoint] = [:],
        context: RenderingContext = .default,
        edgeColor: (@Sendable (StateLayoutModel.EdgeLayout) -> Color?)? = nil
    ) throws -> Data {
        let layout = StateLayoutModel(diagram: stateDiagram, positionOverrides: positionOverrides)
        let view = StateDiagramSnapshotView(
            layout: layout, padding: context.padding, palette: context.palette, edgeColor: edgeColor)
        return try engine.render(
            view, contentSize: layout.contentSize, scale: context.scale, padding: context.padding)
    }
}

/// Renders a `PackageDiagram` to PNG via the shared `PackageLayoutModel` + `PackageDiagramSnapshotView`.
@MainActor
public struct PackageImageRenderer {
    private let engine = DiagramImageRenderer()

    public init() {}

    public func renderPNG(
        packageDiagram: PackageDiagram,
        positionOverrides: [String: CGPoint] = [:],
        context: RenderingContext = .default,
        colors: GraphColorOverrides = .plain
    ) throws -> Data {
        let layout = PackageLayoutModel(diagram: packageDiagram, positionOverrides: positionOverrides)
        let view = PackageDiagramSnapshotView(
            layout: layout, padding: context.padding, palette: context.palette,
            nodeColor: colors.node, edgeColor: colors.edge)
        return try engine.render(
            view, contentSize: layout.contentSize, scale: context.scale, padding: context.padding)
    }
}

/// Renders a `CallGraph` to PNG via the shared `CallGraphLayoutModel` + `CallGraphSnapshotView`.
@MainActor
public struct CallGraphImageRenderer {
    private let engine = DiagramImageRenderer()

    public init() {}

    public func renderPNG(
        callGraph: CallGraph,
        positionOverrides: [String: CGPoint] = [:],
        context: RenderingContext = .default,
        colors: GraphColorOverrides = .plain
    ) throws -> Data {
        let layout = CallGraphLayoutModel(graph: callGraph, positionOverrides: positionOverrides)
        let view = CallGraphSnapshotView(
            layout: layout, padding: context.padding, palette: context.palette,
            nodeColor: colors.node, edgeColor: colors.edge)
        return try engine.render(
            view, contentSize: layout.contentSize, scale: context.scale, padding: context.padding)
    }
}
