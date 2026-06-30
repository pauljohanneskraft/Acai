import CoreGraphics
import Foundation
import SwiftUI
import UMLDiagram

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
        scale: CGFloat = 2,
        padding: CGFloat = DiagramImageRenderer.defaultPadding,
        palette: DiagramPalette = .light,
        messageColor: (@Sendable (SequenceLayoutModel.MessageLayout) -> Color?)? = nil
    ) throws -> Data {
        let layout = SequenceLayoutModel(diagram: sequenceDiagram, positionOverrides: positionOverrides)
        let view = SequenceDiagramSnapshotView(
            layout: layout, padding: padding, palette: palette, messageColor: messageColor)
        return try engine.render(view, contentSize: layout.contentSize, scale: scale, padding: padding)
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
        scale: CGFloat = 2,
        padding: CGFloat = DiagramImageRenderer.defaultPadding,
        palette: DiagramPalette = .light,
        edgeColor: (@Sendable (StateLayoutModel.EdgeLayout) -> Color?)? = nil
    ) throws -> Data {
        let layout = StateLayoutModel(diagram: stateDiagram, positionOverrides: positionOverrides)
        let view = StateDiagramSnapshotView(
            layout: layout, padding: padding, palette: palette, edgeColor: edgeColor)
        return try engine.render(view, contentSize: layout.contentSize, scale: scale, padding: padding)
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
        scale: CGFloat = 2,
        padding: CGFloat = DiagramImageRenderer.defaultPadding,
        palette: DiagramPalette = .light,
        nodeColor: (@Sendable (String) -> Color?)? = nil,
        edgeColor: (@Sendable (String, String) -> Color?)? = nil
    ) throws -> Data {
        let layout = PackageLayoutModel(diagram: packageDiagram, positionOverrides: positionOverrides)
        let view = PackageDiagramSnapshotView(
            layout: layout, padding: padding, palette: palette, nodeColor: nodeColor, edgeColor: edgeColor)
        return try engine.render(view, contentSize: layout.contentSize, scale: scale, padding: padding)
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
        scale: CGFloat = 2,
        padding: CGFloat = DiagramImageRenderer.defaultPadding,
        palette: DiagramPalette = .light,
        nodeColor: (@Sendable (String) -> Color?)? = nil,
        edgeColor: (@Sendable (String, String) -> Color?)? = nil
    ) throws -> Data {
        let layout = CallGraphLayoutModel(graph: callGraph, positionOverrides: positionOverrides)
        let view = CallGraphSnapshotView(
            layout: layout, padding: padding, palette: palette, nodeColor: nodeColor, edgeColor: edgeColor)
        return try engine.render(view, contentSize: layout.contentSize, scale: scale, padding: padding)
    }
}
