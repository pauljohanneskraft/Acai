/// Groups a package diagram's module declarations into one Mermaid subgraph per project, the
/// counterpart of `PackageProjectClusters` for the flowchart renderers.
///
/// Nodes whose `project` is `nil` — every node of a single-project folder — are declared at the top
/// level, so a single-project diagram is unchanged.
struct PackageProjectSubgraphs {

    /// - Parameter node: renders one module's declaration, without indentation.
    func lines(nodes: [PackageDiagram.Node], node: (PackageDiagram.Node) -> String) -> [String] {
        let grouped = Dictionary(grouping: nodes) { $0.project }
        guard grouped.keys.contains(where: { $0 != nil }) else {
            return nodes.map { "    \(node($0))" }
        }

        var lines = (grouped[nil] ?? []).map { "    \(node($0))" }
        for (index, project) in grouped.keys.compactMap({ $0 }).sorted().enumerated() {
            lines.append("    subgraph project\(index)[\"\(project.mermaidLabelEscaped)\"]")
            lines.append(contentsOf: (grouped[project] ?? []).map { "        \(node($0))" })
            lines.append("    end")
        }
        return lines
    }
}
