import Foundation

/// Renders a `PackageDiagram` to a Mermaid `flowchart`.
///
/// Each module is a node labelled with its coupling metrics and shaded by its
/// distance from the main sequence; edges carry the cross-module reference weight.
public struct PackageDiagramMermaidRenderer: Sendable {
    private let theme: DiagramTheme?
    private let nodeColor: (@Sendable (String) -> String?)?
    private let edgeColor: (@Sendable (String, String) -> String?)?

    public init(
        theme: DiagramTheme? = nil,
        nodeColor: (@Sendable (String) -> String?)? = nil,
        edgeColor: (@Sendable (String, String) -> String?)? = nil
    ) {
        self.theme = theme
        self.nodeColor = nodeColor
        self.edgeColor = edgeColor
    }

    public func render(_ diagram: PackageDiagram) -> String {
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

        // Link index tracks each emitted edge so an override can colour it via `linkStyle`.
        var linkIndex = 0
        var linkStyles: [String] = []
        for edge in diagram.edges {
            guard let from = idMap[edge.from], let to = idMap[edge.to] else { continue }
            lines.append("    \(from) -->|\(edge.weight)| \(to)")
            if let color = edgeColor?(edge.from, edge.to) {
                linkStyles.append("    linkStyle \(linkIndex) stroke:\(color),stroke-width:2px")
            }
            linkIndex += 1
        }

        for node in diagram.nodes {
            guard let safe = idMap[node.id] else { continue }
            // Keep the distance-zone fill; a delta override adds a coloured border.
            var style = "    style \(safe) fill:\(node.zoneColorHex)"
            if let border = nodeColor?(node.id) { style += ",stroke:\(border),stroke-width:3px" }
            lines.append(style)
        }
        lines.append(contentsOf: linkStyles)

        return lines.joined(separator: "\n") + "\n"
    }

    private func nodeLabel(_ node: PackageDiagram.Node) -> String {
        let instability = String(format: "%.2f", node.instability)
        let abstractness = String(format: "%.2f", node.abstractness)
        let types = node.typeCount == 1 ? "1 type" : "\(node.typeCount) types"
        return "\(node.name)\nI=\(instability) A=\(abstractness)\n\(types)"
    }

}
