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
final class CallGraphViewModel: ObservableObject, LayoutBackedCanvas {
    let graph: CallGraph

    /// Per-method centre overrides, keyed by node id.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    let history = DiagramHistoryManager<[String: CGPoint]>()

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

    // MARK: - LayoutBackedCanvas

    var allNodeIDs: [String] { layout.nodes.map(\.id) }

    func nodeFrame(_ id: String) -> CGRect? { layout.frame(for: id) }

    var defaultNodeSize: CGSize { CGSize(width: 120, height: 52) }
}
