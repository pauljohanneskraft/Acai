import SwiftUI
import UMLCore
#if os(macOS)
import AppKit
#endif

/// View model for the custom diagram editor.
@MainActor
final class CustomDiagramViewModel: ObservableObject {
    var diagramID: UUID?
    weak var browserModel: ProjectBrowserViewModel?

    @Published var nodes: [CustomDiagram.Node] = []
    @Published var edges: [CustomDiagram.Edge] = []
    @Published var selectedNodeIDs: Set<UUID> = []
    @Published var selectedEdgeID: UUID?
    @Published var selectionRect: CGRect?
    /// When set, the user is in "draw relationship" mode: dragging from a node creates an edge.
    @Published var pendingRelationshipKind: Relationship.Kind?
    /// While dragging to draw a relationship, the source node.
    @Published var relationshipDragSourceID: UUID?
    /// The current endpoint (canvas coords) of the relationship being drawn.
    @Published var relationshipDragEndpoint: CGPoint?

    /// Actual measured sizes of rendered node views (updated by GeometryReader).
    var measuredNodeSizes: [UUID: CGSize] = [:]

    // MARK: - Undo / Redo

    /// Snapshot type that captures the undoable portion of the diagram state.
    struct DiagramSnapshot: Equatable, Sendable {
        var nodes: [CustomDiagram.Node]
        var edges: [CustomDiagram.Edge]
    }

    /// History manager backing Cmd+Z / Shift+Cmd+Z.
    let history = DiagramHistoryManager<DiagramSnapshot>()

    /// Whether there is a state to undo to.
    var canUndo: Bool { history.canUndo }

    /// Whether there is a state to redo to.
    var canRedo: Bool { history.canRedo }

    /// Captures the current state as a checkpoint before a mutation.
    func recordUndo() {
        history.checkpoint(DiagramSnapshot(nodes: nodes, edges: edges))
    }

    /// Undo the last action, restoring the previous diagram state.
    func undo() {
        let current = DiagramSnapshot(nodes: nodes, edges: edges)
        guard let previous = history.undo(current: current) else { return }
        nodes = previous.nodes
        edges = previous.edges
        save()
    }

    /// Redo the last undone action.
    func redo() {
        let current = DiagramSnapshot(nodes: nodes, edges: edges)
        guard let next = history.redo(current: current) else { return }
        nodes = next.nodes
        edges = next.edges
        save()
    }

    init() {}

    func configure(diagramID: UUID, browserModel: ProjectBrowserViewModel) {
        self.diagramID = diagramID
        self.browserModel = browserModel
        loadFromStore()
    }

    private func loadFromStore() {
        guard let diagramID, let diagram = browserModel?.customDiagram(for: diagramID) else { return }
        nodes = diagram.nodes
        edges = diagram.edges
    }

    // MARK: - Node CRUD

    func addNode(kind: CustomDiagramNodeKind, name: String, at position: CGPoint) {
        recordUndo()
        let node = CustomDiagram.Node(
            name: name,
            content: kind.defaultContent(),
            positionX: Double(position.x),
            positionY: Double(position.y)
        )
        nodes.append(node)
        save()
    }

    func removeNode(_ nodeID: UUID) {
        recordUndo()
        nodes.removeAll { $0.id == nodeID }
        edges.removeAll { $0.sourceNodeID == nodeID || $0.targetNodeID == nodeID }
        selectedNodeIDs.remove(nodeID)
        save()
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
        for id in selectedNodeIDs {
            nodes.removeAll { $0.id == id }
            edges.removeAll { $0.sourceNodeID == id || $0.targetNodeID == id }
        }
        selectedNodeIDs.removeAll()
        save()
    }

    func moveNode(_ nodeID: UUID, to position: CGPoint) {
        if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
            nodes[idx].positionX = Double(position.x)
            nodes[idx].positionY = Double(position.y)
        }
    }

    func resizeNode(_ nodeID: UUID, width: CGFloat, height: CGFloat) {
        if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
            nodes[idx].width = max(80, Double(width))
            nodes[idx].height = max(50, Double(height))
        }
    }

    /// Increase the draw order of a node so it renders on top of siblings in the same layer.
    func moveNodeHigher(_ nodeID: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        recordUndo()
        let isContainer = nodes[idx].isResizable
        let siblings = nodes.filter { $0.isResizable == isContainer && $0.id != nodeID }
        let maxOrder = siblings.map(\.drawOrder).max() ?? 0
        if nodes[idx].drawOrder <= maxOrder {
            nodes[idx].drawOrder = maxOrder + 1
        }
        save()
    }

    /// Decrease the draw order of a node so it renders below siblings in the same layer.
    func moveNodeLower(_ nodeID: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        recordUndo()
        let isContainer = nodes[idx].isResizable
        let siblings = nodes.filter { $0.isResizable == isContainer && $0.id != nodeID }
        let minOrder = siblings.map(\.drawOrder).min() ?? 0
        if nodes[idx].drawOrder >= minOrder {
            nodes[idx].drawOrder = minOrder - 1
        }
        save()
    }

    func updateNode(_ nodeID: UUID, name: String? = nil, kind: CustomDiagramNodeKind? = nil) {
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
                    nodes[idx].content = kind.defaultContent()
                }
            }
            save()
        }
    }

    // MARK: - Edge CRUD

    func addEdge(from sourceID: UUID, to targetID: UUID, kind: Relationship.Kind) {
        recordUndo()
        let edge = CustomDiagram.Edge(sourceNodeID: sourceID, targetNodeID: targetID, kind: kind)
        edges.append(edge)
        save()
    }

    func removeEdge(_ edgeID: UUID) {
        recordUndo()
        edges.removeAll { $0.id == edgeID }
        if selectedEdgeID == edgeID { selectedEdgeID = nil }
        save()
    }

    func updateEdge(_ edgeID: UUID, sourceID: UUID, targetID: UUID, kind: Relationship.Kind) {
        guard let idx = edges.firstIndex(where: { $0.id == edgeID }) else { return }
        recordUndo()
        edges[idx].sourceNodeID = sourceID
        edges[idx].targetNodeID = targetID
        edges[idx].kind = kind
        save()
    }

    // MARK: - Selection

    func selectNode(_ nodeID: UUID, extending: Bool) {
        if extending {
            if selectedNodeIDs.contains(nodeID) {
                selectedNodeIDs.remove(nodeID)
            } else {
                selectedNodeIDs.insert(nodeID)
            }
        } else {
            selectedNodeIDs = [nodeID]
        }
    }

    func selectNodes(in rect: CGRect) {
        selectedNodeIDs = Set(nodes.filter { node in
            let pos = CGPoint(x: node.positionX, y: node.positionY)
            return rect.contains(pos)
        }.map(\.id))
    }

    func clearSelection() {
        selectedNodeIDs.removeAll()
        selectedEdgeID = nil
    }

    /// Record an undo checkpoint for an upcoming drag or resize gesture.
    /// Call this once at the **beginning** of a gesture, before positions change.
    func recordUndoForGesture() {
        recordUndo()
    }

    // MARK: - Persistence

    func save() {
        guard let diagramID, var diagram = browserModel?.customDiagram(for: diagramID) else { return }
        diagram.nodes = nodes
        diagram.edges = edges
        browserModel?.updateCustomDiagram(diagramID: diagramID, diagram: diagram)
    }

    func saveCanvasState(scale: CGFloat, offset: CGPoint) {
        guard let diagramID, var diagram = browserModel?.customDiagram(for: diagramID) else { return }
        diagram.nodes = nodes
        diagram.edges = edges
        diagram.canvasScale = Double(scale)
        diagram.canvasOffsetX = Double(offset.x)
        diagram.canvasOffsetY = Double(offset.y)
        browserModel?.updateCustomDiagram(diagramID: diagramID, diagram: diagram)
    }

    // MARK: - Helpers

    func nodePosition(_ nodeID: UUID) -> CGPoint? {
        guard let node = nodes.first(where: { $0.id == nodeID }) else { return nil }
        return CGPoint(x: node.positionX, y: node.positionY)
    }

    func nodeSize(_ nodeID: UUID) -> CGSize {
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
                CustomDiagram.Node.Content.type(content).stereotype != nil
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
        default:
            // Simple labeled elements (actor, use case, component, etc.)
            let width = max(100, CGFloat(node.name.count) * 8.5 + 40)
            return CGSize(width: width, height: 60)
        }
    }

    func nodeRect(_ nodeID: UUID) -> CGRect {
        let pos = nodePosition(nodeID) ?? .zero
        let size = nodeSize(nodeID)
        return CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2, width: size.width, height: size.height)
    }

}
