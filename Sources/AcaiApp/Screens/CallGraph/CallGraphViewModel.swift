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
    @Published private(set) var emptyReason: DiagramEmptyReason = .codebase

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

    /// Reads the graph, not `layout`, which rebuilds the whole layout on every read.
    var isEmpty: Bool { graph.nodes.isEmpty }

    private func rebuild() {
        let built = build(scope: scope, filter: filter)
        graph = built.graph
        diff = built.diff
        emptyReason = resolvedEmptyReason()
    }

    private func build(
        scope: CallGraphScope, filter: AcaiQuality.Selector?
    ) -> (graph: CallGraph, diff: CallGraphDiff?) {
        let callGraphFilter = CallGraphFilter(artifact: artifact, filter: filter)
        let new = callGraphFilter.apply(to: CallGraphBuilder(scope: scope).build(from: artifact))
        guard let comparisonArtifact else { return (new, nil) }
        let old = callGraphFilter.apply(to: CallGraphBuilder(scope: scope).build(from: comparisonArtifact))
        let diff = CallGraphDiff(old: old, new: new)
        return (diff.union, diff)
    }

    /// Probes each widening rather than reading what is merely set: an artifact with no resolved calls
    /// is empty however it is scoped, and Reset Scope there would do nothing.
    private func resolvedEmptyReason() -> DiagramEmptyReason {
        guard graph.nodes.isEmpty else { return .codebase }
        if scope != .wholeCodebase, !build(scope: .wholeCodebase, filter: filter).graph.nodes.isEmpty {
            return .scope
        }
        if filter != nil, !build(scope: scope, filter: nil).graph.nodes.isEmpty { return .filter }
        return .codebase
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

    /// Non-color complement to `nodeDeltaColor(id:)`, feeding the node's badge overlay. `nil` when
    /// unchanged or not in delta mode.
    func nodeDeltaStatus(id: String) -> DeltaStatus? {
        guard let diff else { return nil }
        let status = diff.status(ofNode: id)
        return status == .unchanged ? nil : status
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
