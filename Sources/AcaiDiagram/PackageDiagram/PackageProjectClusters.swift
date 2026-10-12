/// One DOT cluster per project; nodes without a project are emitted flat.
struct PackageProjectClusters {
    let theme: DiagramTheme?

    /// - Parameter node: renders one module's DOT line, including its indentation and newline.
    func render(nodes: [PackageDiagram.Node], node: (PackageDiagram.Node) -> String) -> String {
        let grouped = Dictionary(grouping: nodes) { $0.project }
        guard grouped.keys.contains(where: { $0 != nil }) else { return nodes.map(node).joined() }

        var out = grouped[nil].map { $0.map(node).joined() } ?? ""
        let projects = grouped.keys.compactMap { $0 }.sorted()
        for (index, project) in projects.enumerated() {
            out += "  subgraph cluster_project_\(index) {\n"
            out += "    label=\"\(project.dotEscaped)\";\n    style=rounded;\n"
            if let theme {
                out += "    color=\"\(theme.nodeBorderColor)\";\n    fontcolor=\"\(theme.fontColor)\";\n"
            }
            out += (grouped[project] ?? []).map { "  " + node($0) }.joined()
            out += "  }\n\n"
        }
        return out
    }
}
