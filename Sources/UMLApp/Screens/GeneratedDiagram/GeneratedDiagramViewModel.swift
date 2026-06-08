import Foundation
import SwiftUI
import UMLCore

@MainActor
final class GeneratedDiagramViewModel: ObservableObject {
    let codebase: Codebase
    let artifact: CodeArtifact

    @Published var nodes: [GeneratedDiagramNode] = []
    @Published var edges: [GeneratedDiagramEdge] = []
    @Published var nodePositions: [String: CGPoint] = [:]
    @Published var nodeSizes: [String: CGSize] = [:]
    /// User-overridden sizes (from resize handles). These take priority over measured sizes.
    @Published var userNodeSizes: [String: CGSize] = [:]
    @Published var selectedNodeIDs: Set<String> = []
    @Published private(set) var hasPerformedMeasuredLayout = false
    @Published var selectionRect: CGRect?

    private var configuration: GeneratedDiagram.Configuration
    private var restoredPositions: [String: CGPoint]?

    init(
        codebase: Codebase,
        artifact: CodeArtifact,
        configuration: GeneratedDiagram.Configuration = .init(),
        restoredPositions: [String: CGPoint]? = nil,
        restoredSizes: [String: CGSize]? = nil
    ) {
        self.codebase = codebase
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

        // Hide whole types whose access level is below the minimum, then build nodes.
        let visibleTypes = resolved.types.filter {
            GeneratedDiagramNode.passesAccessFilter($0.accessLevel, minimum: configuration.minimumAccessLevel)
        }
        nodes = visibleTypes.map { .init(from: $0, configuration: configuration) }

        // Build edges, filtering by configuration. Edges to hidden types are dropped
        // because their endpoints are no longer in the known-type set.
        let typeIds = Set(visibleTypes.map(\.id))
        edges = buildEdges(from: resolved.relationships, knownTypeIds: typeIds)

        // Estimate sizes and run initial layout.
        for node in nodes {
            nodeSizes[node.id] = estimateSize(for: node)
        }

        applyOrPerformLayout()
    }

    private func buildEdges(
        from relationships: [Relationship],
        knownTypeIds: Set<String>
    ) -> [GeneratedDiagramEdge] {
        guard configuration.showRelationships else { return [] }
        return relationships.compactMap { rel in
            guard knownTypeIds.contains(rel.source),
                  knownTypeIds.contains(rel.target),
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

            return GeneratedDiagramEdge(from: rel)
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

    func applyConfiguration(_ newConfig: GeneratedDiagram.Configuration, artifact: CodeArtifact) {
        let groupingChanged = newConfig.grouping != configuration.grouping
        self.configuration = newConfig
        // Drop saved positions when the grouping changes so the layout actually reflows;
        // otherwise keep current positions so unrelated tweaks don't disturb them.
        self.restoredPositions = groupingChanged ? nil : nodePositions
        hasPerformedMeasuredLayout = false
        buildDiagram()
    }

    // MARK: - Layout

    /// Extra space baked into every node's layout footprint so neighbours never touch
    /// and small size-estimate errors can't produce visual overlap.
    private static let layoutMargin: CGFloat = 28

    func performLayout() {
        let engine = SugiyamaLayoutEngine()
        let margin = Self.layoutMargin
        let inputs = nodes.map {
            // Lay out using the node's *displayed* size (user-resized > measured > estimated),
            // inflated by a uniform margin so the result has breathing room.
            let size = effectiveSize(for: $0.id)
            return SugiyamaLayoutEngine.NodeInput(
                id: $0.id,
                size: CGSize(width: size.width + margin * 2, height: size.height + margin * 2),
                group: groupKey(for: $0)
            )
        }
        let edgeInputs = edges.map {
            SugiyamaLayoutEngine.EdgeInput(sourceID: $0.sourceID, targetID: $0.targetID, kind: $0.kind)
        }
        // Any grouping mode partitions the graph per group so each group box is a
        // contiguous, non-overlapping block; ungrouped uses the component-based layout.
        let result = configuration.grouping == .none
            ? engine.layout(nodes: inputs, edges: edgeInputs)
            : engine.layoutByGroup(nodes: inputs, edges: edgeInputs)
        nodePositions = result.positions
    }

    /// The clustering key for a node under the active grouping mode.
    private func groupKey(for node: GeneratedDiagramNode) -> String? {
        switch configuration.grouping {
        case .none:
            return nil
        case .directory:
            return node.directoryPath
        case .product:
            return node.productGroup
        }
    }

    // MARK: - Grouping Boxes

    /// A labelled box wrapping all nodes of one group (a directory level or a compiled
    /// product). `depth` is its nesting level (1 = outermost), used for z-order and inset.
    struct GroupingBox: Identifiable {
        let id: String
        let label: String
        let rect: CGRect
        let depth: Int
    }

    /// Nested bounding boxes for the active grouping mode, computed from the *current* node
    /// rects so they always wrap their nodes after drags, resizes and measured-size updates.
    /// One box per path prefix of every node's group key (so `Sources/UMLCore/ClassDiagram`
    /// yields a box at each of the three levels), giving the multi-layer nesting. Empty when
    /// grouping is `.none`. The hierarchical layout keeps each prefix contiguous, so the
    /// boxes nest without overlapping.
    var groupingBoxes: [GroupingBox] {
        guard configuration.grouping != .none else { return [] }
        var byPrefix: [String: (label: String, depth: Int, rect: CGRect)] = [:]
        for node in nodes {
            guard let group = groupKey(for: node), let rect = nodeRect(for: node.id) else { continue }
            let components = group.split(separator: "/").map(String.init)
            for depth in 1...components.count {
                let key = components.prefix(depth).joined(separator: "/")
                if let existing = byPrefix[key] {
                    byPrefix[key] = (existing.label, existing.depth, existing.rect.union(rect))
                } else {
                    byPrefix[key] = (components[depth - 1], depth, rect)
                }
            }
        }
        // Every box reserves a node-free strip at its top for its title tab — so even a
        // single-node box shows its name (boxes are drawn *behind* the nodes, so a tab that
        // overlaps a node would be hidden). Each ancestor level adds one more tab-height, so
        // a parent's tab clears its child's even when they share a top-left corner. Draw
        // shallower (outer) boxes first so deeper ones render on top.
        let maxDepth = byPrefix.values.map(\.depth).max() ?? 1
        let titleStrip: CGFloat = 30
        let levelStep: CGFloat = 30
        return byPrefix
            .map { key, value in
                let inset = titleStrip + CGFloat(maxDepth - value.depth) * levelStep
                return GroupingBox(
                    id: key, label: value.label,
                    rect: value.rect.insetBy(dx: -inset, dy: -inset), depth: value.depth
                )
            }
            .sorted { $0.depth < $1.depth }
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

    // MARK: - Size Estimation

    private func estimateSize(for node: GeneratedDiagramNode) -> CGSize {
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
