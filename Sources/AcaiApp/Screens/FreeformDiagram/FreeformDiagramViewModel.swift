import SwiftUI
import AcaiCore
import AcaiRender
#if os(macOS)
import AppKit
#endif

/// View model for the freeform diagram editor.
@MainActor
final class FreeformDiagramViewModel: ObservableObject, DiagramHistoryHosting, CanvasInteraction,
    FreeformEditingContext {
    var diagramID: UUID?
    weak var browserModel: ProjectBrowserViewModel?

    // MARK: - Editing collaborators
    //
    // Each owns one editing domain over the shared nodes/edges (via `FreeformEditingContext`), so
    // this view model stays the canvas / history / selection / persistence facade the views observe.

    /// Lifelines, ordered messages, and combined fragments.
    lazy var sequence = SequenceEditor(context: self)
    /// States and labeled transitions.
    lazy var state = StateMachineEditor(context: self)
    /// Type members and inline text (name / member / note) editing.
    lazy var members = TypeMemberEditor(context: self)
    /// Cut / copy / paste of the node-and-edge selection.
    lazy var clipboard = SelectionClipboard(context: self)

    @Published var nodes: [FreeformDiagram.Node] = []
    @Published var edges: [FreeformDiagram.Edge] = []
    @Published var selectedNodeIDs: Set<String> = [] {
        didSet {
            // Keep the click order in sync no matter how the set is mutated (taps, marquee,
            // shared canvas gestures): drop deselected ids, append newly selected ones.
            selectionOrder.removeAll { !selectedNodeIDs.contains($0) }
            for id in selectedNodeIDs where !selectionOrder.contains(id) {
                selectionOrder.append(id)
            }
        }
    }
    /// Selected node ids in the order they were selected. Edge/message creation reads this so
    /// "first selected → second selected" determines the arrow direction (a `Set` alone would
    /// make the direction random).
    @Published private(set) var selectionOrder: [String] = []
    @Published var selectedEdgeID: String?
    @Published var selectionRect: CGRect?
    /// When set, the user is in "draw relationship" mode: dragging from a node creates an edge.
    @Published var pendingRelationshipKind: Relationship.Kind?
    /// While dragging to draw a relationship, the source node.
    @Published var relationshipDragSourceID: String?
    /// The current endpoint (canvas coords) of the relationship being drawn.
    @Published var relationshipDragEndpoint: CGPoint?

    /// Actual measured sizes of rendered node views (updated by GeometryReader).
    var measuredNodeSizes: [String: CGSize] = [:]

    // MARK: - Undo / Redo

    /// Snapshot type that captures the undoable portion of the diagram state.
    struct DiagramSnapshot: Equatable, Sendable {
        var nodes: [FreeformDiagram.Node]
        var edges: [FreeformDiagram.Edge]
    }

    /// History manager backing Cmd+Z / Shift+Cmd+Z.
    let history = DiagramHistoryManager<DiagramSnapshot>()

    /// Undoable state: the nodes and edges. (See `DiagramHistoryHosting`.)
    var historySnapshot: DiagramSnapshot {
        get { DiagramSnapshot(nodes: nodes, edges: edges) }
        set {
            nodes = newValue.nodes
            edges = newValue.edges
        }
    }

    /// Persist after an undo/redo restores a snapshot.
    func persistAfterHistoryChange() { save() }

    init() {}

    func configure(diagramID: UUID, browserModel: ProjectBrowserViewModel) {
        self.diagramID = diagramID
        self.browserModel = browserModel
        loadFromStore()
    }

    private func loadFromStore() {
        guard let diagramID, let diagram = browserModel?.freeformDiagram(for: diagramID) else { return }
        nodes = diagram.nodes
        edges = diagram.edges
        // Reloading replaces the whole diagram, so any in-memory undo history is now stale.
        history.clear()
    }

    // MARK: - Node CRUD

    func addNode(kind: FreeformDiagramNodeKind, name: String, at position: CGPoint) {
        recordUndo()
        let node = FreeformDiagram.Node(
            name: name,
            content: FreeformDiagram.Node.Content.makeDefault(for: kind),
            positionX: Double(position.x),
            positionY: Double(position.y)
        )
        nodes.append(node)
        save()
    }

    func removeNode(_ nodeID: String) {
        recordUndo()
        removeNodes([nodeID])
        save()
    }

    /// Remove the given nodes and any edges touching them, and drop them from the selection.
    /// Does **not** record undo or save — callers own that so a batch removal is one undo step.
    func removeNodes(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        nodes.removeAll { ids.contains($0.id) }
        edges.removeAll { ids.contains($0.sourceNodeID) || ids.contains($0.targetNodeID) }
        selectedNodeIDs.subtract(ids)
    }

    /// Delete the current selection (the selected edge and/or all selected nodes) as a single
    /// undoable action, so one ⌘Z restores everything at once.
    func deleteSelection() {
        guard !selectedNodeIDs.isEmpty || selectedEdgeID != nil else { return }
        recordUndo()
        if let edgeID = selectedEdgeID {
            edges.removeAll { $0.id == edgeID }
            selectedEdgeID = nil
        }
        removeNodes(selectedNodeIDs)
        save()
    }

    func moveNode(_ nodeID: String, to position: CGPoint) {
        if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
            nodes[idx].positionX = Double(position.x)
            // Lifelines slide horizontally only — vertically they are pinned to the shared
            // header row, exactly like the generated sequence view.
            if case .lifeline = nodes[idx].content {} else {
                nodes[idx].positionY = Double(position.y)
            }
        }
    }

    func resizeNode(_ nodeID: String, width: CGFloat, height: CGFloat) {
        if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
            nodes[idx].width = max(80, Double(width))
            nodes[idx].height = max(50, Double(height))
        }
    }

    /// Increase the draw order of a node so it renders on top of siblings in the same layer.
    func moveNodeHigher(_ nodeID: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        let isContainer = nodes[idx].isResizable
        let siblings = nodes.filter { $0.isResizable == isContainer && $0.id != nodeID }
        let maxOrder = siblings.map(\.drawOrder).max() ?? 0
        guard nodes[idx].drawOrder <= maxOrder else { return }
        recordUndo()
        nodes[idx].drawOrder = maxOrder + 1
        save()
    }

    /// Decrease the draw order of a node so it renders below siblings in the same layer.
    func moveNodeLower(_ nodeID: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        let isContainer = nodes[idx].isResizable
        let siblings = nodes.filter { $0.isResizable == isContainer && $0.id != nodeID }
        let minOrder = siblings.map(\.drawOrder).min() ?? 0
        guard nodes[idx].drawOrder >= minOrder else { return }
        recordUndo()
        nodes[idx].drawOrder = minOrder - 1
        save()
    }

    func updateNode(_ nodeID: String, name: String? = nil, kind: FreeformDiagramNodeKind? = nil) {
        if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
            recordUndo()
            if let name { nodes[idx].name = name }
            if let kind {
                // When switching between type kinds, preserve existing members.
                switch (nodes[idx].content, kind) {
                case (.type(var existing), .type(let newTK)):
                    existing.typeKind = newTK
                    nodes[idx].content = .type(existing)
                default:
                    nodes[idx].content = FreeformDiagram.Node.Content.makeDefault(for: kind)
                }
            }
            save()
        }
    }

    // MARK: - Edge CRUD

    func addEdge(from sourceID: String, to targetID: String, kind: Relationship.Kind) {
        recordUndo()
        var edge = FreeformDiagram.Edge(sourceNodeID: sourceID, targetNodeID: targetID, kind: kind)
        // An edge between two lifelines is a sequence message: SequenceEditor owns that rule and
        // stamps the next time-order / synchronous kind (both editable in the inspector).
        sequence.reclassify(&edge)
        edges.append(edge)
        save()
    }

    func removeEdge(_ edgeID: String) {
        recordUndo()
        edges.removeAll { $0.id == edgeID }
        if selectedEdgeID == edgeID { selectedEdgeID = nil }
        save()
    }

    func updateEdge(_ edgeID: String, sourceID: String, targetID: String, kind: Relationship.Kind) {
        guard let idx = edges.firstIndex(where: { $0.id == edgeID }) else { return }
        recordUndo()
        edges[idx].sourceNodeID = sourceID
        edges[idx].targetNodeID = targetID
        edges[idx].kind = kind
        // A message exists iff between two lifelines: re-pointing onto two lifelines promotes the
        // edge to a message, re-pointing away demotes it (same undo step). SequenceEditor owns
        // that rule so the canvas and inspector classify the edge consistently.
        sequence.reclassify(&edges[idx])
        save()
    }

    // MARK: - Selection

    /// Drives the shared `selectAll` / marquee defaults on `CanvasInteraction`.
    var allNodeIDs: [String] { nodes.map(\.id) }

    // Selection uses the shared `CanvasInteraction` defaults; this hook drops the freeform-only
    // selected edge whenever the node selection is replaced (click, marquee, select-all, clear),
    // so a node and an edge can never appear selected at once.
    func selectionWillReplace() {
        selectedEdgeID = nil
    }

    // MARK: - Persistence

    func save() {
        guard let diagramID, var diagram = browserModel?.freeformDiagram(for: diagramID) else { return }
        diagram.nodes = nodes
        diagram.edges = edges
        browserModel?.freeforms.update(diagramID: diagramID, diagram: diagram)
    }

    func saveCanvasState(scale: CGFloat, offset: CGPoint) {
        guard let diagramID, var diagram = browserModel?.freeformDiagram(for: diagramID) else { return }
        diagram.nodes = nodes
        diagram.edges = edges
        diagram.canvasScale = Double(scale)
        diagram.canvasOffsetX = Double(offset.x)
        diagram.canvasOffsetY = Double(offset.y)
        browserModel?.freeforms.update(diagramID: diagramID, diagram: diagram)
    }

    // MARK: - Helpers

    func nodePosition(_ nodeID: String) -> CGPoint? {
        guard let node = nodes.first(where: { $0.id == nodeID }) else { return nil }
        return CGPoint(x: node.positionX, y: node.positionY)
    }

    /// `CanvasInteraction` size accessor (freeform diagrams compute this in `nodeSize`).
    func effectiveSize(for id: String) -> CGSize {
        nodeSize(id)
    }

    func nodeSize(_ nodeID: String) -> CGSize {
        guard let node = nodes.first(where: { $0.id == nodeID }) else {
            return CGSize(width: 120, height: 60)
        }
        // If the user has explicitly resized a container node, use that.
        if let w = node.width, let h = node.height {
            return CGSize(width: w, height: h)
        }
        // Prefer the actual measured size from the rendered view.
        if let measured = measuredNodeSizes[nodeID] {
            return measured
        }
        switch node.content {
        case .type(let content):
            let lineHeight: CGFloat = 18
            let hasStereotype = content.stereotype != nil ||
                FreeformDiagram.Node.Content.type(content).stereotype != nil
            let headerHeight: CGFloat = hasStereotype ? 48 : 32
            let propHeight = CGFloat(max(content.properties.count, 1)) * lineHeight
            let methodHeight = CGFloat(max(content.methods.count, 1)) * lineHeight
            let caseHeight = content.enumCases.isEmpty ? 0 : CGFloat(content.enumCases.count) * lineHeight
            let padding: CGFloat = 16
            let height = headerHeight + propHeight + methodHeight + caseHeight + 3 + padding
            let allNames = [node.name] + content.properties.map(\.name)
                + content.methods.map(\.name)
            let maxChars = allNames.map(\.count).max() ?? 10
            let width = max(180, CGFloat(maxChars) * 7.5 + 28)
            return CGSize(width: min(width, 400), height: height)
        case .note(let text):
            let lines = max(text.components(separatedBy: .newlines).count, 2)
            let width = max(140, CGFloat(max(node.name.count, text.count / max(lines, 1))) * 7.5 + 32)
            return CGSize(width: min(width, 300), height: CGFloat(lines) * 18 + 48)
        case .package, .boundary, .subsystem:
            // Default container size before user resizes.
            let width = max(200, CGFloat(node.name.count) * 8.5 + 60)
            return CGSize(width: width, height: 150)
        case .lifeline:
            // Match the generated sequence view's header sizing exactly.
            return CGSize(
                width: SequenceLayoutModel.headerWidth(for: node.name),
                height: SequenceLayoutModel.headerHeight
            )
        case .state(let kind):
            // Match the generated state view's node sizing exactly.
            return StateLayoutModel.estimatedSize(
                for: .init(id: node.id, name: node.name, kind: kind)
            )
        case .method:
            // Match the generated call-graph node sizing (monospaced label box).
            let width = max(120, CGFloat(node.name.count) * 7 + 32)
            return CGSize(width: min(width, 320), height: 52)
        default:
            // Simple labeled elements (actor, use case, component, etc.)
            let width = max(100, CGFloat(node.name.count) * 8.5 + 40)
            return CGSize(width: width, height: 60)
        }
    }

    func nodeRect(_ nodeID: String) -> CGRect {
        let pos = nodePosition(nodeID) ?? .zero
        let size = nodeSize(nodeID)
        return CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2, width: size.width, height: size.height)
    }

}
