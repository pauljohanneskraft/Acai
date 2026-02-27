import SwiftUI
import UMLCore

/// View model for the custom diagram editor.
@MainActor
final class CustomDiagramEditorViewModel: ObservableObject {
    var diagramID: UUID?
    weak var browserModel: ProjectBrowserViewModel?

    @Published var nodes: [CustomDiagramNode] = []
    @Published var edges: [CustomDiagramEdge] = []
    @Published var selectedNodeIDs: Set<UUID> = []
    @Published var selectedEdgeID: UUID? = nil
    @Published var selectionRect: CGRect? = nil
    /// When set, the user is in "draw relationship" mode: dragging from a node creates an edge.
    @Published var pendingRelationshipKind: Relationship.Kind? = nil
    /// While dragging to draw a relationship, the source node.
    @Published var relationshipDragSourceID: UUID? = nil
    /// The current endpoint (canvas coords) of the relationship being drawn.
    @Published var relationshipDragEndpoint: CGPoint? = nil

    /// Actual measured sizes of rendered node views (updated by GeometryReader).
    var measuredNodeSizes: [UUID: CGSize] = [:]

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

    func addNode(kind: DiagramElementKind, name: String, at position: CGPoint) {
        let node = CustomDiagramNode(
            name: name,
            content: kind.defaultContent(),
            positionX: Double(position.x),
            positionY: Double(position.y)
        )
        nodes.append(node)
        save()
    }

    func removeNode(_ nodeID: UUID) {
        nodes.removeAll { $0.id == nodeID }
        edges.removeAll { $0.sourceNodeID == nodeID || $0.targetNodeID == nodeID }
        selectedNodeIDs.remove(nodeID)
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
        let isContainer = nodes[idx].isResizable
        let siblings = nodes.filter { $0.isResizable == isContainer && $0.id != nodeID }
        let minOrder = siblings.map(\.drawOrder).min() ?? 0
        if nodes[idx].drawOrder >= minOrder {
            nodes[idx].drawOrder = minOrder - 1
        }
        save()
    }

    func updateNode(_ nodeID: UUID, name: String? = nil, kind: DiagramElementKind? = nil) {
        if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
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
        let edge = CustomDiagramEdge(sourceNodeID: sourceID, targetNodeID: targetID, kind: kind)
        edges.append(edge)
        save()
    }

    func removeEdge(_ edgeID: UUID) {
        edges.removeAll { $0.id == edgeID }
        if selectedEdgeID == edgeID { selectedEdgeID = nil }
        save()
    }

    func updateEdge(_ edgeID: UUID, sourceID: UUID, targetID: UUID, kind: Relationship.Kind) {
        guard let idx = edges.firstIndex(where: { $0.id == edgeID }) else { return }
        edges[idx].sourceNodeID = sourceID
        edges[idx].targetNodeID = targetID
        edges[idx].kind = kind
        save()
    }

    func startRelationshipDrawing(from nodeID: UUID) {
        selectedNodeIDs = [nodeID]
        // The user can then shift-click a second node and use the catalog to create the edge.
    }

    // MARK: - Member CRUD (type nodes only)

    func addProperty(to nodeID: UUID, name: String, type: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        content.properties.append(CustomMember(name: name, type: type))
        nodes[idx].content = .type(content)
        save()
    }

    /// Parse a single string like "name: String" into a property and add it.
    func addPropertyFromText(to nodeID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? trimmed
        let type = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        addProperty(to: nodeID, name: name, type: type)
    }

    func addMethod(to nodeID: UUID, name: String, returnType: String, parameters: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        content.methods.append(CustomMember(name: name, type: returnType, parameters: parameters))
        nodes[idx].content = .type(content)
        save()
    }

    /// Parse a single string like "doWork(input: Int): String" into a method and add it.
    func addMethodFromText(to nodeID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var name = trimmed
        var params = ""
        var returnType = ""

        if let parenStart = trimmed.firstIndex(of: "("),
           let parenEnd = trimmed.firstIndex(of: ")") {
            name = String(trimmed[trimmed.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
            params = String(trimmed[trimmed.index(after: parenStart)..<parenEnd])
            let afterParen = trimmed[trimmed.index(after: parenEnd)...]
            if let colonIdx = afterParen.firstIndex(of: ":") {
                returnType = String(afterParen[afterParen.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            }
        } else if let colonIdx = trimmed.firstIndex(of: ":") {
            name = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            returnType = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        }

        addMethod(to: nodeID, name: name, returnType: returnType, parameters: params)
    }

    func removeProperty(from nodeID: UUID, memberID: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        content.properties.removeAll { $0.id == memberID }
        nodes[idx].content = .type(content)
        save()
    }

    func removeMethod(from nodeID: UUID, memberID: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        content.methods.removeAll { $0.id == memberID }
        nodes[idx].content = .type(content)
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

    // MARK: - Inline Editing

    func updateNodeName(_ nodeID: UUID, name: String) {
        if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
            nodes[idx].name = name
            save()
        }
    }

    func updatePropertyText(_ nodeID: UUID, memberID: UUID, text: String) {
        guard let ni = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[ni].content,
              let mi = content.properties.firstIndex(where: { $0.id == memberID }) else { return }
        let parts = text.split(separator: ":", maxSplits: 1)
        content.properties[mi].name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? text
        if parts.count > 1 {
            content.properties[mi].type = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        nodes[ni].content = .type(content)
        save()
    }

    func updateMethodText(_ nodeID: UUID, memberID: UUID, text: String) {
        guard let ni = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[ni].content,
              let mi = content.methods.firstIndex(where: { $0.id == memberID }) else { return }
        if let parenStart = text.firstIndex(of: "("),
           let parenEnd = text.firstIndex(of: ")") {
            content.methods[mi].name = String(text[text.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
            content.methods[mi].parameters = String(text[text.index(after: parenStart)..<parenEnd])
            let afterParen = text[text.index(after: parenEnd)...]
            if let colonIdx = afterParen.firstIndex(of: ":") {
                content.methods[mi].type = String(afterParen[afterParen.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            }
        } else {
            content.methods[mi].name = text
        }
        nodes[ni].content = .type(content)
        save()
    }

    func addInlineProperty(to nodeID: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        content.properties.append(CustomMember(name: "newProperty", type: "Type"))
        nodes[idx].content = .type(content)
        save()
    }

    func addInlineMethod(to nodeID: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .type(var content) = nodes[idx].content else { return }
        content.methods.append(CustomMember(name: "newMethod", type: "Void"))
        nodes[idx].content = .type(content)
        save()
    }

    /// Update the free-form text of a note node.
    func updateNoteText(_ nodeID: UUID, text: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }),
              case .note = nodes[idx].content else { return }
        nodes[idx].content = .note(text: text)
        save()
    }

    // MARK: - Relationship Drawing

    func beginRelationshipDrag(from nodeID: UUID) {
        relationshipDragSourceID = nodeID
    }

    func updateRelationshipDrag(to point: CGPoint) {
        relationshipDragEndpoint = point
    }

    func completeRelationshipDrag(at point: CGPoint) {
        guard let sourceID = relationshipDragSourceID,
              let kind = pendingRelationshipKind else {
            cancelRelationshipDrag()
            return
        }
        // Find target node under the drop point.
        if let targetNode = nodes.first(where: { node in
            let rect = CGRect(
                x: node.positionX - nodeSize(node.id).width / 2,
                y: node.positionY - nodeSize(node.id).height / 2,
                width: nodeSize(node.id).width,
                height: nodeSize(node.id).height
            )
            return rect.contains(point)
        }), targetNode.id != sourceID {
            addEdge(from: sourceID, to: targetNode.id, kind: kind)
        }
        cancelRelationshipDrag()
    }

    func cancelRelationshipDrag() {
        relationshipDragSourceID = nil
        relationshipDragEndpoint = nil
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
                NodeContent.type(content).stereotype != nil
            let headerHeight: CGFloat = hasStereotype ? 48 : 32
            let propHeight = CGFloat(max(content.properties.count, 1)) * lineHeight
            let methodHeight = CGFloat(max(content.methods.count, 1)) * lineHeight
            let caseHeight = content.enumCases.isEmpty ? 0 : CGFloat(content.enumCases.count) * lineHeight
            let padding: CGFloat = 16
            let height = headerHeight + propHeight + methodHeight + caseHeight + 3 + padding
            let maxChars = ([node.name] + content.properties.map(\.name) + content.methods.map(\.name)).map(\.count).max() ?? 10
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
