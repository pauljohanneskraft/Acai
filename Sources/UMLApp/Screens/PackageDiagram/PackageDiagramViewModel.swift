import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLLibrary
import UMLRender

/// Backs the movement-only package diagram view. The `PackageDependencyDiagram` is derived from
/// the (enriched) artifact, so it always tracks the code — unlike sequence/state there is no
/// configuration to choose and no analysis failure to surface. The user may drag module nodes;
/// those positions are the only editable, undoable state. Conforms to `CanvasInteraction` so it
/// reuses the shared canvas (pan/zoom, drag, marquee, undo/redo).
@MainActor
final class PackageDiagramViewModel: ObservableObject, LayoutBackedCanvas {
    let diagram: PackageDependencyDiagram

    /// Per-module centre overrides, keyed by module id.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    let history = DiagramHistoryManager<[String: CGPoint]>()

    // MARK: - Init

    init(artifact: CodeArtifact, restoredPositions: [String: CGPoint] = [:]) {
        self.diagram = artifact.enriched(configuration: artifact.standardLanguageConfiguration)
            .packageDependencyDiagram()
        self.positionOverrides = restoredPositions
    }

    // MARK: - Layout

    /// Current geometry, honouring node drags.
    var layout: PackageLayoutModel {
        PackageLayoutModel(diagram: diagram, positionOverrides: positionOverrides)
    }

    /// The module backing a given node id, for the inspector.
    func module(for id: String) -> PackageDependencyDiagram.Node? {
        diagram.nodes.first { $0.id == id }
    }

    // MARK: - LayoutBackedCanvas

    var allNodeIDs: [String] { layout.nodes.map(\.id) }

    func nodeFrame(_ id: String) -> CGRect? { layout.frame(for: id) }

    var defaultNodeSize: CGSize { CGSize(width: 140, height: 72) }
}
