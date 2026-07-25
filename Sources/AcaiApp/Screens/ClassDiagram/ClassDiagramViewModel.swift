import Foundation
import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiDiff
import AcaiRender

@MainActor
final class ClassDiagramViewModel: ObservableObject, DiagramHistoryHosting, CanvasInteraction {
    let codebase: Codebase
    let artifact: CodeArtifact
    /// The "old" revision for delta mode, or `nil` for a normal diagram.
    private let comparisonArtifact: CodeArtifact?
    /// The artifact-level diff when in delta mode; drives per-edge tinting.
    private var diff: ArtifactDiff?
    /// O(1) status lookups derived from `diff` once per build, so per-element tinting stays cheap on
    /// every SwiftUI render pass (vs. `ArtifactDiff.status(of:)`'s per-call linear scan).
    private var edgeStatus: (@Sendable (Relationship) -> DeltaStatus)?
    private var typeStatus: (@Sendable (String) -> DeltaStatus)?

    @Published var nodes: [GeneratedDiagramNode] = []
    @Published var edges: [GeneratedDiagramEdge] = []
    @Published var nodePositions: [String: CGPoint] = [:]
    @Published var nodeSizes: [String: CGSize] = [:]
    /// User-overridden sizes (from resize handles). These take priority over measured sizes.
    @Published var userNodeSizes: [String: CGSize] = [:]
    @Published var selectedNodeIDs: Set<String> = []
    @Published var isMultiSelectActive = false
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
        restoredSizes: [String: CGSize]? = nil,
        comparisonArtifact: CodeArtifact? = nil
    ) {
        self.codebase = codebase
        self.artifact = artifact
        self.comparisonArtifact = comparisonArtifact
        self.configuration = configuration
        self.restoredPositions = restoredPositions
        self.model = DiagramLayoutModel(
            artifact: artifact, configuration: configuration,
            languages: artifact.standardLanguageResolver
        )
        if let restoredSizes {
            self.userNodeSizes = restoredSizes
        }
        buildDiagram()
    }

    // MARK: - Build Diagram

    private func buildDiagram() {
        // In delta mode, render the union of both revisions so removed types/edges still appear and
        // can be tinted; otherwise render the working-tree artifact directly.
        let renderArtifact: CodeArtifact
        if let comparisonArtifact {
            let differ = ArtifactDiffer()
            let computed = differ.diff(old: comparisonArtifact, new: artifact)
            diff = computed
            edgeStatus = computed.relationshipStatusLookup()
            typeStatus = computed.typeStatusLookup()
            renderArtifact = differ.unionArtifact(old: comparisonArtifact, new: artifact)
        } else {
            diff = nil
            edgeStatus = nil
            typeStatus = nil
            renderArtifact = artifact
        }
        model = DiagramLayoutModel(
            artifact: renderArtifact, configuration: configuration,
            languages: renderArtifact.standardLanguageResolver
        )
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

    /// Drives the shared `selectAll` / marquee defaults on `CanvasInteraction`.
    var allNodeIDs: [String] { nodes.map(\.id) }

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

    /// Whether the diagram is rendering a delta against a comparison revision.
    var isDeltaMode: Bool { diff != nil }

    /// The delta tint for an edge (added green / removed red / changed amber), or `nil` when the
    /// edge is unchanged or the diagram isn't in delta mode.
    func deltaColor(for edge: GeneratedDiagramEdge) -> Color? {
        guard let edgeStatus else { return nil }
        let relationship = Relationship(kind: edge.kind, source: edge.sourceID, target: edge.targetID)
        guard let hex = edgeStatus(relationship).deltaHex else { return nil }
        return Color(hex: hex)
    }

    /// The delta fill for a type node (added green / removed red / changed amber), or `nil` when
    /// the type is unchanged or the diagram isn't in delta mode.
    func deltaColor(for node: GeneratedDiagramNode) -> Color? {
        guard let typeStatus, let hex = typeStatus(node.id).deltaHex else { return nil }
        return Color(hex: hex)
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
        // In delta mode the exported PNG carries the same tints as the on-screen canvas. Precompute
        // the colours into Sendable maps so the render closures don't capture the main-actor model.
        var edgeColor: (@Sendable (GeneratedDiagramEdge) -> Color?)?
        var nodeColor: (@Sendable (GeneratedDiagramNode) -> Color?)?
        if isDeltaMode {
            let edgeColors = Dictionary(edges.compactMap { e in deltaColor(for: e).map { (e.id, $0) } },
                                        uniquingKeysWith: { first, _ in first })
            let nodeColors = Dictionary(nodes.compactMap { n in deltaColor(for: n).map { (n.id, $0) } },
                                        uniquingKeysWith: { first, _ in first })
            edgeColor = { edgeColors[$0.id] }
            nodeColor = { nodeColors[$0.id] }
        }
        let laidOut = LaidOutDiagram(
            nodes: nodes, edges: edges, positions: nodePositions, sizes: sizes, groupingBoxes: groupingBoxes)
        return try ClassImageRenderer().renderPNG(
            laidOut: laidOut,
            context: RenderingContext(scale: scale),
            colors: ClassColorOverrides(edge: edgeColor, node: nodeColor)
        )
    }
}
