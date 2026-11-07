import CoreGraphics
import AcaiCore
import AcaiRender

extension ClassDiagramViewModel {
    var rotorPlan: DiagramRotorPlan {
        rotorPlanCache.plan { freshRotorPlan }
    }

    private var freshRotorPlan: DiagramRotorPlan {
        let names = nodeNamesByID
        return DiagramRotorPlan(
            elements: nodes.removingDuplicates(by: \.id).compactMap { node in
                nodeRect(for: node.id).map { frame in
                    DiagramRotorPlan.Element(id: node.id, label: node.name, delta: deltaBadge(for: node), frame: frame)
                }
            },
            connections: edges.removingDuplicates(by: \.id).compactMap { edge in
                guard let source = nodeRect(for: edge.sourceID), let target = nodeRect(for: edge.targetID) else {
                    return nil
                }
                return DiagramRotorPlan.Element(
                    connection: edge.rotorID, label: edgeAccessibility(for: edge, nodeNames: names).label,
                    delta: deltaStatus(for: edge), from: source, to: target
                )
            },
            groupingBoxes: groupingBoxes.map { box in
                DiagramRotorPlan.Element(id: box.rotorID, label: box.label, delta: nil, frame: box.rect)
            }
        )
    }
}

extension DiagramLayoutModel.GroupingBox {
    var rotorID: String {
        "diagram.groupingBox.\(id)"
    }
}

extension GeneratedDiagramEdge {
    var rotorID: String {
        "diagram.edge.\(id)"
    }

    var accessibilityIdentifier: String {
        "diagram.edge.\(sourceID)->\(targetID)"
    }
}
