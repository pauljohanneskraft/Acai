import CoreGraphics
import AcaiRender

extension CallGraphViewModel {
    var rotorPlan: DiagramRotorPlan {
        let layout = layout
        let labels = layout.nodeLabels
        return DiagramRotorPlan(
            elements: layout.nodes.map { node in
                DiagramRotorPlan.Element(
                    id: node.id, label: node.node.label, delta: nodeDeltaStatus(id: node.id), frame: node.rect
                )
            },
            connections: layout.edges.compactMap { edge in
                guard let source = layout.frame(for: edge.from), let target = layout.frame(for: edge.to) else {
                    return nil
                }
                return DiagramRotorPlan.Element(
                    connection: edge.accessibilityID, label: edgeDescription(edge, labels: labels).summary,
                    delta: edgeDeltaStatus(from: edge.from, to: edge.to), from: source, to: target
                )
            }
        )
    }

    func edgeDescription(
        _ edge: CallGraphLayoutModel.EdgeLayout, labels: [String: String]
    ) -> DiagramElementDescription {
        DiagramElementDescription(
            dependencyFrom: labels[edge.from] ?? edge.from,
            to: labels[edge.to] ?? edge.to,
            callSites: edge.weight,
            delta: edgeDeltaStatus(from: edge.from, to: edge.to)
        )
    }
}

extension CallGraphLayoutModel {
    var nodeLabels: [String: String] {
        Dictionary(nodes.map { ($0.id, $0.node.label) }, uniquingKeysWith: { first, _ in first })
    }
}

extension CallGraphLayoutModel.EdgeLayout {
    var accessibilityID: String {
        "diagram.callEdge.\(from)->\(to)"
    }
}
