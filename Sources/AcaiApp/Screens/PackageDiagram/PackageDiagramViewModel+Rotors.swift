import CoreGraphics
import AcaiRender

extension PackageDiagramViewModel {
    var rotorPlan: DiagramRotorPlan {
        let layout = layout
        let names = layout.nodeNames
        return DiagramRotorPlan(
            elements: layout.nodes.map { node in
                DiagramRotorPlan.Element(
                    id: node.id, label: node.node.name, delta: nodeDeltaStatus(id: node.id), frame: node.rect
                )
            },
            connections: layout.edges.compactMap { edge in
                guard let source = layout.frame(for: edge.from), let target = layout.frame(for: edge.to) else {
                    return nil
                }
                return DiagramRotorPlan.Element(
                    connection: edge.accessibilityID, label: edgeDescription(edge, names: names).summary,
                    delta: edgeDeltaStatus(from: edge.from, to: edge.to), from: source, to: target
                )
            }
        )
    }

    func edgeDescription(
        _ edge: PackageLayoutModel.EdgeLayout, names: [String: String]
    ) -> DiagramElementDescription {
        DiagramElementDescription(
            dependencyFrom: names[edge.from] ?? edge.from,
            to: names[edge.to] ?? edge.to,
            references: edge.weight,
            delta: edgeDeltaStatus(from: edge.from, to: edge.to)
        )
    }
}

extension PackageLayoutModel {
    var nodeNames: [String: String] {
        Dictionary(nodes.map { ($0.id, $0.node.name) }, uniquingKeysWith: { first, _ in first })
    }
}

extension PackageLayoutModel.EdgeLayout {
    var accessibilityID: String {
        "diagram.packageEdge.\(from)->\(to)"
    }
}
