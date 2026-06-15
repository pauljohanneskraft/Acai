/// Renders a `CallGraph` to a Mermaid `flowchart`.
///
/// Each method is a node labelled `Type.method`; edges carry the call multiplicity when a
/// caller hits the same target more than once. Out-of-scope callee leaves are styled lighter.
public struct CallGraphMermaidRenderer: Sendable {
    private let theme: DiagramTheme?

    public init(theme: DiagramTheme? = nil) {
        self.theme = theme
    }

    public func render(_ graph: CallGraph) -> String {
        var lines: [String] = []
        if let title = graph.title {
            lines.append("---")
            lines.append("title: \(title)")
            lines.append("---")
        }
        if let theme { lines.append(theme.mermaidInit()) }
        lines.append("flowchart LR")

        var allocator = MermaidIDAllocator()
        var idMap: [String: String] = [:]
        for node in graph.nodes {
            let safe = allocator.id(for: node.id)
            idMap[node.id] = safe
            lines.append("    \(safe)[\"\(node.label.mermaidLabelEscaped)\"]")
        }

        for edge in graph.edges {
            guard let from = idMap[edge.from], let to = idMap[edge.to] else { continue }
            if edge.weight > 1 {
                lines.append("    \(from) -->|\(edge.weight)| \(to)")
            } else {
                lines.append("    \(from) --> \(to)")
            }
        }

        for node in graph.nodes where !node.inScope {
            guard let safe = idMap[node.id] else { continue }
            lines.append("    style \(safe) fill:#f5f5f5,stroke-dasharray: 3 3")
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
