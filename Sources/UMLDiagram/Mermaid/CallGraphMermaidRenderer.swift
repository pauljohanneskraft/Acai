/// Renders a `CallGraph` to a Mermaid `flowchart`.
///
/// Each method is a node labelled `Type.method`; edges carry the call multiplicity when a
/// caller hits the same target more than once. Out-of-scope callee leaves are styled lighter.
public struct CallGraphMermaidRenderer: Sendable {
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

        let (arrows, linkStyles) = edgeLines(graph, idMap: idMap)
        lines += arrows
        lines += nodeStyleLines(graph, idMap: idMap)
        lines += linkStyles
        return lines.joined(separator: "\n") + "\n"
    }

    /// The call arrows, plus a `linkStyle` directive for each edge the override colours (Mermaid
    /// requires those after all links are declared, so they're returned separately).
    private func edgeLines(_ graph: CallGraph, idMap: [String: String]) -> (arrows: [String], linkStyles: [String]) {
        var arrows: [String] = []
        var linkStyles: [String] = []
        var linkIndex = 0
        for edge in graph.edges {
            guard let from = idMap[edge.from], let to = idMap[edge.to] else { continue }
            arrows.append(edge.weight > 1 ? "    \(from) -->|\(edge.weight)| \(to)" : "    \(from) --> \(to)")
            if let color = edgeColor?(edge.from, edge.to) {
                linkStyles.append("    linkStyle \(linkIndex) stroke:\(color),stroke-width:2px")
            }
            linkIndex += 1
        }
        return (arrows, linkStyles)
    }

    /// A per-node override colours a node's border (added/removed/changed); out-of-scope leaves keep
    /// their dashed light style. When the override is nil the output is unchanged.
    private func nodeStyleLines(_ graph: CallGraph, idMap: [String: String]) -> [String] {
        graph.nodes.compactMap { node in
            guard let safe = idMap[node.id] else { return nil }
            if let color = nodeColor?(node.id) {
                let base = node.inScope ? "" : "fill:#f5f5f5,stroke-dasharray: 3 3,"
                return "    style \(safe) \(base)stroke:\(color),stroke-width:3px"
            } else if !node.inScope {
                return "    style \(safe) fill:#f5f5f5,stroke-dasharray: 3 3"
            }
            return nil
        }
    }
}
