import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLDiff
import UMLLibrary
import UMLRender

/// Backs the movement-only package diagram view. The `PackageDiagram` is derived from
/// the (enriched) artifact, so it always tracks the code — unlike sequence/state there is no
/// configuration to choose and no analysis failure to surface. The user may drag module nodes;
/// those positions are the only editable, undoable state. Conforms to `CanvasInteraction` so it
/// reuses the shared canvas (pan/zoom, drag, marquee, undo/redo).
@MainActor
final class PackageDiagramViewModel: ObservableObject, LayoutBackedCanvas {
    let diagram: PackageDiagram

    /// Per-module centre overrides, keyed by module id.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    let history = DiagramHistoryManager<[String: CGPoint]>()

    /// The package-level diff when comparing against another revision; drives node/edge tinting.
    private let diff: PackageDiagramDiff?

    // MARK: - Init

    init(artifact: CodeArtifact, restoredPositions: [String: CGPoint] = [:], comparisonArtifact: CodeArtifact? = nil) {
        let new = PackageDiagramBuilder().build(
            from: artifact.enriched(configuration: artifact.standardLanguageConfiguration))
        if let comparisonArtifact {
            let old = PackageDiagramBuilder().build(
                from: comparisonArtifact.enriched(configuration: comparisonArtifact.standardLanguageConfiguration))
            let diff = PackageDiagramDiff(old: old, new: new)
            self.diff = diff
            self.diagram = diff.union
        } else {
            self.diff = nil
            self.diagram = new
        }
        self.positionOverrides = restoredPositions
    }

    /// Whether the diagram is rendering a delta against a comparison revision.
    var isDeltaMode: Bool { diff != nil }

    /// The delta fill for a module node, or `nil` when unchanged / not in delta mode.
    func nodeDeltaColor(id: String) -> Color? {
        guard let diff, let hex = diff.status(ofNode: id).deltaHex else { return nil }
        return Color(hex: hex)
    }

    /// The delta stroke for a dependency edge, or `nil` when unchanged / not in delta mode.
    func edgeDeltaColor(from: String, to: String) -> Color? {
        guard let diff, let hex = diff.status(ofEdgeFrom: from, to: to).deltaHex else { return nil }
        return Color(hex: hex)
    }

    // MARK: - Layout

    /// Current geometry, honouring node drags.
    var layout: PackageLayoutModel {
        PackageLayoutModel(diagram: diagram, positionOverrides: positionOverrides)
    }

    /// The module backing a given node id, for the inspector.
    func module(for id: String) -> PackageDiagram.Node? {
        diagram.nodes.first { $0.id == id }
    }

    // MARK: - LayoutBackedCanvas

    var allNodeIDs: [String] { layout.nodes.map(\.id) }

    func nodeFrame(_ id: String) -> CGRect? { layout.frame(for: id) }

    var defaultNodeSize: CGSize { CGSize(width: 140, height: 72) }

    // MARK: - Image Export

    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        try DiagramImageRenderer().renderPNG(
            packageDiagram: diagram,
            positionOverrides: positionOverrides,
            scale: scale
        )
    }
}
