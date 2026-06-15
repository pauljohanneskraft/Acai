import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender

/// Backs the movement-only call-graph view. The `CallGraph` is derived from the artifact for the
/// chosen `scope`, so it always tracks the code — like package, there is no configuration popup
/// and no analysis failure to surface. The user may drag method nodes; those positions are the
/// only editable, undoable state. Conforms to `CanvasInteraction` so it reuses the shared canvas.
@MainActor
final class CallGraphViewModel: ObservableObject, DiagramHistoryHosting, CanvasInteraction {
    let graph: CallGraph

    /// Per-method centre overrides, keyed by node id.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    // MARK: - Undo / Redo

    let history = DiagramHistoryManager<[String: CGPoint]>()

    var historySnapshot: [String: CGPoint] {
        get { positionOverrides }
        set { positionOverrides = newValue }
    }

    // MARK: - Init

    init(artifact: CodeArtifact, scope: CallGraphScope, restoredPositions: [String: CGPoint] = [:]) {
        self.graph = artifact.callGraph(scope: scope)
        self.positionOverrides = restoredPositions
    }

    // MARK: - Layout

    /// Current geometry, honouring node drags.
    var layout: CallGraphLayoutModel {
        CallGraphLayoutModel(graph: graph, positionOverrides: positionOverrides)
    }

    /// The node backing a given id, for the inspector.
    func node(for id: String) -> CallGraph.Node? {
        graph.nodes.first { $0.id == id }
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
        layout.frame(for: id)?.size ?? CGSize(width: 120, height: 52)
    }

    /// Method boxes are fixed-size; resizing is a no-op.
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
