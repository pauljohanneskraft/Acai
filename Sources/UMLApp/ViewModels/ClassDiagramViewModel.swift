import Foundation
import SwiftUI
import UMLCore

@MainActor
final class ClassDiagramViewModel: ObservableObject {
    let artifact: CodeArtifact

    @Published var nodes: [DiagramNode] = []
    @Published var edges: [DiagramEdge] = []
    @Published var nodePositions: [String: CGPoint] = [:]
    @Published var nodeSizes: [String: CGSize] = [:]
    /// User-overridden sizes (from resize handles). These take priority over measured sizes.
    @Published var userNodeSizes: [String: CGSize] = [:]
    @Published var selectedNodeIDs: Set<String> = []
    @Published private(set) var hasPerformedMeasuredLayout = false
    @Published var selectionRect: CGRect?

    private var configuration: DiagramConfiguration
    private var restoredPositions: [String: CGPoint]?

    /// Standard initializer — no configuration, no restored positions.
    init(artifact: CodeArtifact) {
        self.artifact = artifact
        self.configuration = DiagramConfiguration()
        self.restoredPositions = nil
        buildDiagram()
    }

    /// Initializer with stored configuration and optional restored positions/sizes.
    init(
        artifact: CodeArtifact,
        configuration: DiagramConfiguration,
        restoredPositions: [String: CGPoint]? = nil,
        restoredSizes: [String: CGSize]? = nil
    ) {
        self.artifact = artifact
        self.configuration = configuration
        self.restoredPositions = restoredPositions
        if let restoredSizes {
            self.userNodeSizes = restoredSizes
        }
        buildDiagram()
    }

    // MARK: - Build Diagram

    private func buildDiagram() {
        var resolved = artifact.resolvingExtensions()

        // Filter out Dart-generated types when the option is enabled.
        if configuration.hideGeneratedDartTypes && artifact.metadata.sourceLanguage == .dart {
            resolved = resolved.filteringGeneratedDartTypes()
        }

        // Build nodes from type declarations, applying configuration filters.
        nodes = resolved.types.map { DiagramNode(from: $0, configuration: configuration) }

        // Build edges, filtering by configuration.
        let typeNames = Set(resolved.types.map(\.name))
        edges = buildEdges(from: resolved.relationships, typeNames: typeNames)

        // Estimate sizes and run initial layout.
        for node in nodes {
            nodeSizes[node.id] = estimateSize(for: node)
        }

        applyOrPerformLayout()
    }

    private func buildEdges(
        from relationships: [Relationship],
        typeNames: Set<String>
    ) -> [DiagramEdge] {
        guard configuration.showRelationships else { return [] }
        return relationships.compactMap { rel in
            guard typeNames.contains(rel.source),
                  typeNames.contains(rel.target),
                  rel.source != rel.target else { return nil }

            switch rel.kind {
            case .inheritance, .conformance:
                guard configuration.showInheritance else { return nil }
            case .composition, .aggregation:
                guard configuration.showComposition else { return nil }
            case .dependency:
                guard configuration.showDependency else { return nil }
            default:
                break
            }

            return DiagramEdge(from: rel)
        }
    }

    private func applyOrPerformLayout() {
        if let restored = restoredPositions, !restored.isEmpty {
            nodePositions = restored
            let missing = nodes.filter { restored[$0.id] == nil }
            if !missing.isEmpty {
                performLayout()
                for (id, pos) in restored {
                    nodePositions[id] = pos
                }
            }
        } else {
            performLayout()
        }
    }

    // MARK: - Apply Configuration

    func applyConfiguration(_ newConfig: DiagramConfiguration, artifact: CodeArtifact) {
        self.configuration = newConfig
        self.restoredPositions = nodePositions // Keep current positions
        hasPerformedMeasuredLayout = false
        buildDiagram()
    }

    // MARK: - Layout

    func performLayout() {
        let engine = SugiyamaLayoutEngine()
        let inputs = nodes.map {
            SugiyamaLayoutEngine.NodeInput(
                id: $0.id,
                size: nodeSizes[$0.id] ?? CGSize(width: 200, height: 100),
                group: $0.directoryGroup
            )
        }
        let edgeInputs = edges.map {
            SugiyamaLayoutEngine.EdgeInput(sourceID: $0.sourceID, targetID: $0.targetID, kind: $0.kind)
        }
        let result = engine.layout(nodes: inputs, edges: edgeInputs)
        nodePositions = result.positions
    }

    // MARK: - Selection

    func selectNode(_ id: String, extending: Bool) {
        if extending {
            if selectedNodeIDs.contains(id) {
                selectedNodeIDs.remove(id)
            } else {
                selectedNodeIDs.insert(id)
            }
        } else {
            selectedNodeIDs = [id]
        }
    }

    func selectAll() {
        selectedNodeIDs = Set(nodes.map(\.id))
    }

    func clearSelection() {
        selectedNodeIDs.removeAll()
    }

    /// Select nodes whose center falls within the given rectangle.
    func selectNodes(in rect: CGRect) {
        selectedNodeIDs = Set(nodes.filter { node in
            guard let pos = nodePositions[node.id] else { return false }
            return rect.contains(pos)
        }.map(\.id))
    }

    // MARK: - Movement & Resize

    func moveNode(_ id: String, to position: CGPoint) {
        nodePositions[id] = position
    }

    func resizeNode(_ id: String, width: CGFloat, height: CGFloat) {
        userNodeSizes[id] = CGSize(width: max(80, width), height: max(50, height))
    }

    /// The effective size for a node: user-overridden > measured > estimated.
    func effectiveSize(for id: String) -> CGSize {
        userNodeSizes[id] ?? nodeSizes[id] ?? CGSize(width: 200, height: 100)
    }

    /// Called when actual rendered sizes are reported via preference keys.
    func updateMeasuredSizes(_ measured: [String: CGSize]) {
        var changed = false
        for (id, size) in measured {
            if let existing = nodeSizes[id] {
                let dx = abs(existing.width - size.width)
                let dy = abs(existing.height - size.height)
                if dx > 2 || dy > 2 {
                    nodeSizes[id] = size
                    changed = true
                }
            } else {
                nodeSizes[id] = size
                changed = true
            }
        }
        if changed && !hasPerformedMeasuredLayout {
            hasPerformedMeasuredLayout = true
            if restoredPositions == nil || restoredPositions!.isEmpty {
                performLayout()
            }
        }
    }

    func nodeRect(for id: String) -> CGRect? {
        guard let pos = nodePositions[id] else { return nil }
        let size = effectiveSize(for: id)
        return CGRect(
            x: pos.x - size.width / 2,
            y: pos.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Backward Compatibility

    /// Single-node selection ID for backward compatibility.
    var selectedNodeID: String? {
        get { selectedNodeIDs.first }
        set {
            if let id = newValue {
                selectedNodeIDs = [id]
            } else {
                selectedNodeIDs.removeAll()
            }
        }
    }

    // MARK: - Size Estimation

    private func estimateSize(for node: DiagramNode) -> CGSize {
        let lineHeight: CGFloat = 18
        let headerHeight: CGFloat = node.stereotype != nil ? 48 : 32

        let visibleProps = node.properties.count
        let visibleMethods = node.methods.count
        let visibleCases = node.enumCases.count

        let propHeight = CGFloat(max(visibleProps, 1)) * lineHeight
        let methodHeight = CGFloat(max(visibleMethods, 1)) * lineHeight
        let caseHeight = visibleCases == 0 ? 0 : CGFloat(visibleCases) * lineHeight
        let dividerCount: CGFloat = visibleCases == 0 ? 2 : 3
        let padding: CGFloat = 16

        let height = headerHeight + propHeight + methodHeight + caseHeight + (dividerCount * 1) + padding

        let allTexts = [node.name]
            + node.properties.map(\.displayText)
            + node.methods.map(\.displayText)
            + node.enumCases.map(\.displayText)
        let maxChars = allTexts.map(\.count).max() ?? 10
        let width = max(180, CGFloat(maxChars) * 7.5 + 28)

        return CGSize(width: min(width, 400), height: height)
    }
}
