import Foundation
import SwiftUI
import UMLCore
import UMLRender

@MainActor
final class ClassDiagramViewModel: ObservableObject, DiagramHistoryHosting, CanvasInteraction {
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

    private(set) var configuration: ClassDiagramConfiguration
    private var restoredPositions: [String: CGPoint]?
    /// Shared, view-independent build + layout core (also used by the CLI image renderer).
    private var model: DiagramLayoutModel

    // MARK: - Undo / Redo

    /// Snapshot type that captures the undoable portion of the generated diagram state.
    struct LayoutSnapshot: Equatable, Sendable {
        var nodePositions: [String: CGPoint]
        var userNodeSizes: [String: CGSize]
    }

    /// History manager backing Cmd+Z / Shift+Cmd+Z.
    let history = DiagramHistoryManager<LayoutSnapshot>()

    /// Undoable state: node positions and user-overridden sizes. (See `DiagramHistoryHosting`.)
    /// Persistence is the view's responsibility (it owns the canvas scale/offset), so there is
    /// no `persistAfterHistoryChange` override — the view pairs `undo()`/`redo()` with
    /// `savePositions()`.
    var historySnapshot: LayoutSnapshot {
        get { LayoutSnapshot(nodePositions: nodePositions, userNodeSizes: userNodeSizes) }
        set {
            nodePositions = newValue.nodePositions
            userNodeSizes = newValue.userNodeSizes
        }
    }

    init(
        codebase: Codebase,
        artifact: CodeArtifact,
        configuration: ClassDiagramConfiguration = .init(),
        restoredPositions: [String: CGPoint]? = nil,
        restoredSizes: [String: CGSize]? = nil
    ) {
        self.codebase = codebase
        self.artifact = artifact
        self.configuration = configuration
        self.restoredPositions = restoredPositions
        self.model = DiagramLayoutModel(artifact: artifact, configuration: configuration)
        if let restoredSizes {
            self.userNodeSizes = restoredSizes
        }
        buildDiagram()
    }

    // MARK: - Build Diagram

    private func buildDiagram() {
        model = DiagramLayoutModel(artifact: artifact, configuration: configuration)
        nodes = model.nodes
        edges = model.edges

        // Estimate sizes and run initial layout.
        for node in nodes {
            nodeSizes[node.id] = DiagramLayoutModel.estimateSize(for: node)
        }

        applyOrPerformLayout()
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

    func applyConfiguration(_ newConfig: ClassDiagramConfiguration, artifact: CodeArtifact) {
        let groupingChanged = newConfig.grouping != configuration.grouping
        self.configuration = newConfig
        // Drop saved positions when the grouping changes so the layout actually reflows;
        // otherwise keep current positions so unrelated tweaks don't disturb them.
        self.restoredPositions = groupingChanged ? nil : nodePositions
        hasPerformedMeasuredLayout = false
        // The rebuilt node set differs, so a stale snapshot must not be restorable.
        history.clear()
        buildDiagram()
    }

    // MARK: - Layout

    func performLayout() {
        // Lay out using each node's *displayed* size (user-resized > measured > estimated).
        let sizes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, effectiveSize(for: $0.id)) })
        nodePositions = model.performLayout(sizes: sizes)
    }

    // MARK: - Grouping Boxes

    /// Nested bounding boxes for the active grouping mode, computed from the *current* node
    /// rects so they always wrap their nodes after drags, resizes and measured-size updates.
    var groupingBoxes: [DiagramLayoutModel.GroupingBox] {
        let sizes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, effectiveSize(for: $0.id)) })
        return model.groupingBoxes(positions: nodePositions, sizes: sizes)
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

    /// Current center of a node (`CanvasInteraction`).
    func nodePosition(_ id: String) -> CGPoint? {
        nodePositions[id]
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

    // MARK: - Image Export

    /// Renders the diagram exactly as currently laid out (including user drags and resizes)
    /// to PNG data, via the shared `DiagramImageRenderer`.
    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        let sizes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, effectiveSize(for: $0.id)) })
        return try DiagramImageRenderer.renderPNG(
            nodes: nodes,
            edges: edges,
            positions: nodePositions,
            sizes: sizes,
            groupingBoxes: groupingBoxes,
            scale: scale
        )
    }
}
