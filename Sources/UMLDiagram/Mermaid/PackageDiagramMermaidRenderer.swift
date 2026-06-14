import Foundation

/// Renders a `PackageDependencyDiagram` to a Mermaid `flowchart`.
///
/// Each module is a node labelled with its coupling metrics and shaded by its
/// distance from the main sequence; edges carry the cross-module reference weight.
public struct PackageDiagramMermaidRenderer: Sendable {
    private let theme: DiagramTheme?

    public init(theme: DiagramTheme? = nil) {
        self.theme = theme
    }

    public func render(_ diagram: PackageDependencyDiagram) -> String {
        var lines: [String] = []
        if let title = diagram.title {
            lines.append("---")
            lines.append("title: \(title)")
            lines.append("---")
        }
        if let theme { lines.append(theme.mermaidInit()) }
        lines.append("flowchart LR")

        var allocator = MermaidIDAllocator()
        var idMap: [String: String] = [:]
        for node in diagram.nodes {
            let safe = allocator.id(for: node.id)
            idMap[node.id] = safe
            lines.append("    \(safe)[\"\(nodeLabel(node).mermaidLabelEscaped)\"]")
        }

        for edge in diagram.edges {
            guard let from = idMap[edge.from], let to = idMap[edge.to] else { continue }
            lines.append("    \(from) -->|\(edge.weight)| \(to)")
        }

        for node in diagram.nodes {
            guard let safe = idMap[node.id] else { continue }
            lines.append("    style \(safe) fill:\(node.zoneColorHex)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func nodeLabel(_ node: PackageDependencyDiagram.Node) -> String {
        let instability = String(format: "%.2f", node.instability)
        let abstractness = String(format: "%.2f", node.abstractness)
        let types = node.typeCount == 1 ? "1 type" : "\(node.typeCount) types"
        return "\(node.name)\nI=\(instability) A=\(abstractness)\n\(types)"
    }

}
