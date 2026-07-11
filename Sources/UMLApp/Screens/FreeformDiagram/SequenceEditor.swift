import CoreGraphics
import Foundation
import UMLDiagram
import UMLRender

/// Sequence editing for the freeform diagram: lifelines, ordered messages, and combined fragments.
///
/// Freeform diagrams render their sequence elements through the same `SequenceLayoutModel` /
/// `SequenceEnsembleView` the generated sequence view uses, so a sequence diagram saved as a
/// freeform diagram looks identical to its generated original — while every lifeline and message
/// stays an ordinary, fully editable node/edge.
@MainActor
final class SequenceEditor {
    private unowned let context: any FreeformEditingContext

    init(context: any FreeformEditingContext) {
        self.context = context
    }

    /// All lifeline nodes, left-to-right by their canvas position.
    var lifelineNodes: [FreeformDiagram.Node] {
        context.nodes
            .filter { if case .lifeline = $0.content { true } else { false } }
            .sorted { $0.positionX < $1.positionX }
    }

    /// Whether an edge is a sequence message: it carries a time order *and* connects two
    /// lifelines. The single predicate behind canvas rendering and the inspector, so an edge
    /// can never show as a message in one place and a relationship in the other.
    func isMessageEdge(_ edge: FreeformDiagram.Edge) -> Bool {
        edge.messageOrder != nil && isLifeline(edge.sourceNodeID) && isLifeline(edge.targetNodeID)
    }

    /// Message edges between lifelines, in time order. Resolves the lifeline id set once so this
    /// stays O(E + N) instead of re-scanning the node array per edge.
    var messageEdges: [FreeformDiagram.Edge] {
        let lifelineIDs = Set(lifelineNodes.map(\.id))
        return context.edges
            .filter { $0.messageOrder != nil
                && lifelineIDs.contains($0.sourceNodeID)
                && lifelineIDs.contains($0.targetNodeID) }
            .sorted { ($0.messageOrder ?? 0) < ($1.messageOrder ?? 0) }
    }

    /// All combined-fragment nodes.
    var fragmentNodes: [FreeformDiagram.Node] {
        context.nodes.filter { if case .fragment = $0.content { true } else { false } }
    }

    /// The shared sequence geometry for this diagram's lifelines, messages and fragments, or
    /// `nil` when the diagram has no lifelines. Participants are keyed by node *id* (names may
    /// repeat), with each lifeline's x pinned to its node position; fragments are keyed by their
    /// node id so frames map back to selectable nodes.
    var sequenceLayout: SequenceLayoutModel? {
        let lifelines = lifelineNodes
        guard !lifelines.isEmpty else { return nil }

        let participants = lifelines.map { node -> SequenceDiagram.Participant in
            let kind: SequenceDiagram.Participant.Kind =
                if case .lifeline(let k) = node.content { k } else { .object }
            return SequenceDiagram.Participant(id: node.id, name: node.id, kind: kind)
        }
        let messages = messageEdges.map { edge in
            SequenceDiagram.Message(
                from: edge.sourceNodeID,
                to: edge.targetNodeID,
                label: edge.label,
                kind: edge.messageKind ?? .synchronous,
                order: edge.messageOrder ?? 0
            )
        }
        let fragments = fragmentNodes.compactMap { node -> SequenceDiagram.Fragment? in
            guard case .fragment(let content) = node.content else { return nil }
            return SequenceDiagram.Fragment(id: node.id, kind: content.kind, operands: content.operands)
        }
        let overrides = Dictionary(
            lifelines.map { ($0.id, CGFloat($0.positionX)) },
            uniquingKeysWith: { first, _ in first }
        )
        return SequenceLayoutModel(
            diagram: SequenceDiagram(participants: participants, messages: messages, fragments: fragments),
            positionOverrides: overrides
        )
    }

    /// Canvas-space y offset of the sequence ensemble: the header row is anchored to the topmost
    /// lifeline node, so lifelines hang from the headers wherever the user has placed them.
    var sequenceAnchorY: CGFloat {
        let minY = lifelineNodes.map(\.positionY).min() ?? 0
        return CGFloat(minY) - SequenceLayoutModel.headerHeight / 2
    }

    // MARK: Editing

    /// The selected lifeline ids in click order (drives message direction: first → second).
    var orderedLifelineSelection: [String] {
        context.selectionOrder.filter { isLifeline($0) }
    }

    /// The next free time-order for a new message: one past the current maximum.
    var nextMessageOrder: Int {
        (context.edges.compactMap(\.messageOrder).max() ?? 0) + 1
    }

    /// Stamp an edge as a sequence message when it connects two lifelines, or clear its message
    /// fields when it doesn't. The single rule behind both new-edge creation and edge re-pointing,
    /// keeping "a message exists iff between two lifelines" enforced in one place.
    func reclassify(_ edge: inout FreeformDiagram.Edge) {
        if isLifeline(edge.sourceNodeID) && isLifeline(edge.targetNodeID) {
            // Repair each field independently so an edge that already qualifies as a message but
            // lacks a kind (older data / manual edits) still gets a sensible default.
            if edge.messageOrder == nil { edge.messageOrder = nextMessageOrder }
            if edge.messageKind == nil { edge.messageKind = .synchronous }
        } else {
            edge.messageOrder = nil
            edge.messageKind = nil
        }
    }

    /// Append a message at the end of the timeline. `sourceID == targetID` makes a self-message.
    func addMessage(from sourceID: String, to targetID: String, kind: SequenceDiagram.Message.Kind) {
        context.recordUndo(coalescingKey: nil)
        var edge = FreeformDiagram.Edge(sourceNodeID: sourceID, targetNodeID: targetID, kind: .dependency)
        edge.messageOrder = nextMessageOrder
        edge.messageKind = kind
        context.edges.append(edge)
        // Select the new message so the inspector opens straight onto label/kind/order.
        context.selectedEdgeID = edge.id
        context.save()
    }

    /// Update a message edge's label, kind and/or time order as one undoable step.
    func updateMessageEdge(
        _ edgeID: String,
        label: String? = nil,
        messageKind: SequenceDiagram.Message.Kind? = nil,
        messageOrder: Int? = nil
    ) {
        guard let idx = context.edges.firstIndex(where: { $0.id == edgeID }) else { return }
        context.recordUndo(coalescingKey: label != nil ? "messageEdgeLabel-\(edgeID)" : nil)
        if let label { context.edges[idx].label = label.isEmpty ? nil : label }
        if let messageKind { context.edges[idx].messageKind = messageKind }
        if let messageOrder { context.edges[idx].messageOrder = messageOrder }
        context.save()
    }

    /// Update a fragment node's operator and/or operands as one undoable step.
    func updateFragment(
        _ nodeID: String,
        kind: SequenceDiagram.Fragment.Kind? = nil,
        operands: [SequenceDiagram.Fragment.Operand]? = nil,
        coalescingKey: AnyHashable? = nil
    ) {
        guard let idx = context.nodes.firstIndex(where: { $0.id == nodeID }),
              case .fragment(var content) = context.nodes[idx].content else { return }
        context.recordUndo(coalescingKey: coalescingKey)
        if let kind { content.kind = kind }
        if let operands { content.operands = operands }
        context.nodes[idx].content = .fragment(content)
        context.save()
    }

    /// Update a lifeline node's participant role (actor, boundary, control, …).
    func updateLifelineKind(_ nodeID: String, kind: SequenceDiagram.Participant.Kind) {
        guard let idx = context.nodes.firstIndex(where: { $0.id == nodeID }),
              case .lifeline = context.nodes[idx].content else { return }
        context.recordUndo(coalescingKey: nil)
        context.nodes[idx].content = .lifeline(kind)
        context.save()
    }

    /// Whether a node is a sequence lifeline.
    func isLifeline(_ nodeID: String) -> Bool {
        if case .lifeline = context.node(nodeID)?.content { return true }
        return false
    }
}
