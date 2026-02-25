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
    @Published var selectedNodeID: String? = nil
    @Published private(set) var hasPerformedMeasuredLayout = false

    init(artifact: CodeArtifact) {
        self.artifact = artifact
        buildDiagram()
    }

    private func buildDiagram() {
        let resolved = artifact.resolvingExtensions()

        // Build nodes from type declarations.
        nodes = resolved.types.map { DiagramNode(from: $0) }

        // Build edges, filtering to relationships where both source and target exist.
        let typeNames = Set(resolved.types.map(\.name))
        edges = resolved.relationships.compactMap { rel in
            guard typeNames.contains(rel.source), typeNames.contains(rel.target) else { return nil }
            // Skip self-referencing edges.
            guard rel.source != rel.target else { return nil }
            return DiagramEdge(from: rel)
        }

        // Estimate sizes and run initial layout.
        for node in nodes {
            nodeSizes[node.id] = estimateSize(for: node)
        }
        performLayout()
    }

    func performLayout() {
        let engine = SugiyamaLayoutEngine()
        let inputs = nodes.map {
            SugiyamaLayoutEngine.NodeInput(id: $0.id, size: nodeSizes[$0.id] ?? CGSize(width: 200, height: 100), group: nil)
        }
        let edgeInputs = edges.map {
            SugiyamaLayoutEngine.EdgeInput(sourceID: $0.sourceID, targetID: $0.targetID, kind: $0.kind)
        }
        let result = engine.layout(nodes: inputs, edges: edgeInputs)
        nodePositions = result.positions
    }

    func moveNode(_ id: String, to position: CGPoint) {
        nodePositions[id] = position
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
            performLayout()
        }
    }

    func nodeRect(for id: String) -> CGRect? {
        guard let pos = nodePositions[id], let size = nodeSizes[id] else { return nil }
        return CGRect(
            x: pos.x - size.width / 2,
            y: pos.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Size Estimation

    private func estimateSize(for node: DiagramNode) -> CGSize {
        let lineHeight: CGFloat = 18
        let headerHeight: CGFloat = node.stereotype != nil ? 48 : 32
        let propHeight = CGFloat(max(node.properties.count, 1)) * lineHeight
        let methodHeight = CGFloat(max(node.methods.count, 1)) * lineHeight
        let caseHeight = node.enumCases.isEmpty ? 0 : CGFloat(node.enumCases.count) * lineHeight
        let dividerCount: CGFloat = node.enumCases.isEmpty ? 2 : 3
        let padding: CGFloat = 16

        let height = headerHeight + propHeight + methodHeight + caseHeight + (dividerCount * 1) + padding

        let allTexts = [node.name] + node.properties.map(\.displayText) + node.methods.map(\.displayText) + node.enumCases.map(\.displayText)
        let maxChars = allTexts.map(\.count).max() ?? 10
        let width = max(180, CGFloat(maxChars) * 7.5 + 28)

        return CGSize(width: min(width, 400), height: height)
    }
}
