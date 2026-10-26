import CoreGraphics
import AcaiCore
import AcaiRender

extension FreeformDiagramViewModel {
    /// `sequenceLayout` is the layout the canvas draws, so lifelines read on the header row they sit on.
    func rotorPlan(sequenceLayout: SequenceLayoutModel?) -> DiagramRotorPlan {
        let names = Dictionary(nodes.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let messageEdges = sequence.messageEdges
        let messageEdgeIDs = Set(messageEdges.map(\.id))
        var elements = (containerLayerNodes + regularLayerNodes).map { node in
            DiagramRotorPlan.Element(
                id: node.id, label: DiagramElementDescription(freeformNode: node).label, delta: nil,
                frame: nodeRect(node.id)
            )
        }
        var connections = edges.filter { !messageEdgeIDs.contains($0.id) }.map { edge in
            DiagramRotorPlan.Element(
                connection: edge.rotorID,
                label: DiagramElementDescription(
                    freeformEdge: edge, sourceName: names[edge.sourceNodeID] ?? "",
                    targetName: names[edge.targetNodeID] ?? ""
                ).summary,
                delta: nil, from: nodeRect(edge.sourceNodeID), to: nodeRect(edge.targetNodeID)
            )
        }
        guard let sequenceLayout else {
            return DiagramRotorPlan(elements: elements, connections: connections)
        }
        let anchorY = sequence.sequenceAnchorY
        let headerMidY = anchorY + SequenceLayoutModel.headerHeight / 2
        elements += sequence.lifelineNodes.map { node in
            let size = nodeSize(node.id)
            return DiagramRotorPlan.Element(
                id: node.id, label: DiagramElementDescription(freeformNode: node).label, delta: nil,
                frame: CGRect(
                    x: node.positionX - size.width / 2, y: headerMidY - size.height / 2,
                    width: size.width, height: size.height
                )
            )
        }
        elements += sequenceLayout.fragments.map { fragment in
            DiagramRotorPlan.Element(
                id: fragment.id, label: fragment.kind.rawValue, delta: nil,
                frame: fragment.tabRect.offsetBy(dx: 0, dy: anchorY)
            )
        }
        connections += sequenceLayout.messages.map { message in
            let edge = messageEdges.indices.contains(message.id) ? messageEdges[message.id] : nil
            return DiagramRotorPlan.Element(
                connection: message.freeformRotorID,
                label: edge.map { DiagramElementDescription(freeformMessage: $0, names: names).summary } ?? "",
                delta: nil,
                midpoint: CGPoint(x: (message.fromX + message.toX) / 2, y: anchorY + message.y)
            )
        }
        return DiagramRotorPlan(elements: elements, connections: connections)
    }
}

extension FreeformDiagram.Edge {
    var rotorID: String {
        "diagram.freeformEdge.\(id)"
    }
}

extension SequenceLayoutModel.MessageLayout {
    var freeformRotorID: String {
        "diagram.freeformMessage.\(id)"
    }
}
