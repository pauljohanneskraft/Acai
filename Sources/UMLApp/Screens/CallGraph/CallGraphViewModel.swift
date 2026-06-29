import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLDiff
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

    /// The call-graph diff when comparing against another revision; drives node/edge tinting.
    private let diff: CallGraphDiff?

    // MARK: - Init

    init(
        artifact: CodeArtifact, scope: CallGraphScope,
        restoredPositions: [String: CGPoint] = [:], comparisonArtifact: CodeArtifact? = nil
    ) {
        let new = artifact.callGraph(scope: scope)
        if let comparisonArtifact {
            let diff = CallGraphDiff(old: comparisonArtifact.callGraph(scope: scope), new: new)
            self.diff = diff
            self.graph = diff.union
        } else {
            self.diff = nil
            self.graph = new
        }
        self.positionOverrides = restoredPositions
    }

    /// Whether the graph is rendering a delta against a comparison revision.
    var isDeltaMode: Bool { diff != nil }

    /// The delta fill for a method node, or `nil` when unchanged / not in delta mode.
    func nodeDeltaColor(id: String) -> Color? {
        guard let diff, let hex = diff.status(ofNode: id).deltaHex else { return nil }
        return Color(hex: hex)
    }

    /// The delta stroke for a call edge, or `nil` when unchanged / not in delta mode.
    func edgeDeltaColor(from: String, to: String) -> Color? {
        guard let diff, let hex = diff.status(ofEdgeFrom: from, to: to).deltaHex else { return nil }
        return Color(hex: hex)
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

    // MARK: - Image Export

    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        try DiagramImageRenderer.renderPNG(
            callGraph: graph,
            positionOverrides: positionOverrides,
            scale: scale
        )
    }
}
