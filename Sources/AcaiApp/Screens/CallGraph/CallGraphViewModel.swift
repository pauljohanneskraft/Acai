import Foundation
import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiDiff
import AcaiLibrary
import AcaiQuality
import AcaiRender

/// Backs the movement-only call-graph view. The `CallGraph` is derived from the artifact for the
/// chosen `scope` and (optional) selector `filter`, so it always tracks the code — like package,
/// there is no configuration popup and no analysis failure to surface. The user may drag method
/// nodes; those positions are the only other editable, undoable state. Conforms to
/// `CanvasInteraction` so it reuses the shared canvas.
@MainActor
final class CallGraphViewModel: ObservableObject, LayoutBackedCanvas {
    private let artifact: CodeArtifact
    private let scope: CallGraphScope
    private let comparisonArtifact: CodeArtifact?

    @Published private(set) var graph: CallGraph
    @Published private(set) var filter: AcaiQuality.Selector?

    /// Per-method centre overrides, keyed by node id.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []
    @Published var isMultiSelectActive = false

    let history = DiagramHistoryManager<[String: CGPoint]>()

    /// The call-graph diff when comparing against another revision; drives node/edge tinting.
    private var diff: CallGraphDiff?

    // MARK: - Init

    init(
        artifact: CodeArtifact, scope: CallGraphScope, filter: AcaiQuality.Selector? = nil,
        restoredPositions: [String: CGPoint] = [:], comparisonArtifact: CodeArtifact? = nil
    ) {
        self.artifact = artifact
        self.scope = scope
        self.comparisonArtifact = comparisonArtifact
        self.filter = filter
        self.graph = CallGraph()
        self.positionOverrides = restoredPositions
        rebuild()
    }

    /// Re-derives the graph for a new filter, keeping node positions (filtering only removes
    /// nodes/edges, it never repositions a surviving one).
    func applyFilter(_ newFilter: AcaiQuality.Selector?) {
        filter = newFilter
        rebuild()
    }

    private func rebuild() {
        let new = filtered(CallGraphBuilder(scope: scope).build(from: artifact))
        if let comparisonArtifact {
            let old = filtered(CallGraphBuilder(scope: scope).build(from: comparisonArtifact))
            let diff = CallGraphDiff(old: old, new: new)
            self.diff = diff
            self.graph = diff.union
        } else {
            self.diff = nil
            self.graph = new
        }
    }

    /// Drops nodes `filter` doesn't match (and edges touching them). Only nodes owned by a type
    /// (`typeName` non-empty) can be matched — a free function has no type to resolve a selector's
    /// module/stereotype/kind/access facets against, so free-function nodes always pass through.
    /// A node whose type can't be resolved back to a declaration also passes through (fails open)
    /// rather than silently vanishing from the graph.
    private func filtered(_ graph: CallGraph) -> CallGraph {
        guard let filter else { return graph }
        let graphView = GraphView(artifact: artifact, languageResolver: artifact.standardLanguageResolver)
        let typesByName = Dictionary(
            artifact.flattened().map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let keptIDs = Set(graph.nodes.filter { node in
            guard !node.typeName.isEmpty else { return true }
            guard let type = typesByName[node.typeName], let match = graphView.node(id: type.id) else { return true }
            return filter.matches(match)
        }.map(\.id))
        return CallGraph(
            title: graph.title,
            nodes: graph.nodes.filter { keptIDs.contains($0.id) },
            edges: graph.edges.filter { keptIDs.contains($0.from) && keptIDs.contains($0.to) },
            coverage: graph.coverage
        )
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

    // MARK: - LayoutBackedCanvas

    var allNodeIDs: [String] { layout.nodes.map(\.id) }

    func nodeFrame(_ id: String) -> CGRect? { layout.frame(for: id) }

    var defaultNodeSize: CGSize { CGSize(width: 120, height: 52) }

    // MARK: - Image Export

    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        try CallGraphImageRenderer().renderPNG(
            callGraph: graph,
            positionOverrides: positionOverrides,
            context: RenderingContext(scale: scale)
        )
    }
}
