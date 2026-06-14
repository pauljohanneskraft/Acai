import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender

/// Backs the movement-only package diagram view. The `PackageDependencyDiagram` is derived from
/// the (enriched) artifact, so it always tracks the code — unlike sequence/state there is no
/// configuration to choose and no analysis failure to surface. The user may drag module nodes;
/// those positions are the only editable, undoable state. Conforms to `CanvasInteraction` so it
/// reuses the shared canvas (pan/zoom, drag, marquee, undo/redo).
@MainActor
final class PackageDiagramViewModel: ObservableObject, DiagramHistoryHosting, CanvasInteraction {
    let diagram: PackageDependencyDiagram

    /// Per-module centre overrides, keyed by module id.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    // MARK: - Undo / Redo

    let history = DiagramHistoryManager<[String: CGPoint]>()

    var historySnapshot: [String: CGPoint] {
        get { positionOverrides }
        set { positionOverrides = newValue }
    }

    // MARK: - Init

    init(artifact: CodeArtifact, restoredPositions: [String: CGPoint] = [:]) {
        self.diagram = artifact.enriched().packageDependencyDiagram()
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

    // MARK: - CanvasInteraction

    func nodePosition(_ id: String) -> CGPoint? {
        guard let frame = layout.frame(for: id) else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    func moveNode(_ id: String, to position: CGPoint) {
        positionOverrides[id] = position
    }

    func effectiveSize(for id: String) -> CGSize {
        layout.frame(for: id)?.size ?? CGSize(width: 140, height: 72)
    }

    /// Module boxes are fixed-size; resizing is a no-op.
    func resizeNode(_ id: String, width: CGFloat, height: CGFloat) {}

    func selectNode(_ id: String, extending: Bool) {
        if extending {
            if selectedNodeIDs.contains(id) { selectedNodeIDs.remove(id) } else { selectedNodeIDs.insert(id) }
        } else {
            selectedNodeIDs = [id]
        }
    }

    func selectNodes(in rect: CGRect) {
        selectedNodeIDs = Set(
            layout.nodes
                .filter { rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
                .map(\.id)
        )
    }

    func clearSelection() { selectedNodeIDs.removeAll() }

    func selectAll() { selectedNodeIDs = Set(layout.nodes.map(\.id)) }
}
