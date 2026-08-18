import Foundation
import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiDiff
import AcaiLibrary
import AcaiQuality
import AcaiRender

@MainActor
final class CallGraphViewModel: ObservableObject, LayoutBackedCanvas {
    private let artifact: CodeArtifact
    private let scope: CallGraphScope
    private let comparisonArtifact: CodeArtifact?

    @Published private(set) var graph: CallGraph
    @Published private(set) var filter: AcaiQuality.Selector?

    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []
    @Published var isMultiSelectActive = false

    let history = DiagramHistoryManager<[String: CGPoint]>()

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

    /// Free functions and nodes whose type can't be resolved back to a declaration always pass
    /// through (fail open) rather than silently vanishing from the graph.
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

    var isDeltaMode: Bool { diff != nil }

    func nodeDeltaColor(id: String) -> Color? {
        guard let diff, let hex = diff.status(ofNode: id).deltaHex else { return nil }
        return Color(hex: hex)
    }

    func edgeDeltaColor(from: String, to: String) -> Color? {
        guard let diff, let hex = diff.status(ofEdgeFrom: from, to: to).deltaHex else { return nil }
        return Color(hex: hex)
    }

    // MARK: - Layout

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
