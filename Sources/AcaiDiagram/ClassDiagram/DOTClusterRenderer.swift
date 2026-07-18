import AcaiCore

/// Groups `TypeDeclaration` values into DOT subgraph clusters by file or namespace.
struct DOTClusterRenderer {
    let options: ClassDiagramOptions

    func renderByFile(types: [TypeDeclaration]) -> String {
        let nodeRenderer = DOTNodeRenderer(options: options)
        let grouped = Dictionary(grouping: types) { $0.location?.filePath ?? "unknown" }
        return grouped.sorted(by: { $0.key < $1.key }).enumerated().map { index, pair in
            let (filePath, fileTypes) = pair
            return "  subgraph cluster_\(index) {\n"
                + clusterOpen(label: filePath.dotEscaped)
                + nodeRenderer.render(types: fileTypes)
                + "  }\n\n"
        }.joined()
    }

    func renderByNamespace(types: [TypeDeclaration]) -> String {
        let nodeRenderer = DOTNodeRenderer(options: options)
        let grouped = Dictionary(grouping: types) { $0.namespace ?? "" }
        return grouped.sorted(by: { $0.key < $1.key }).enumerated().map { index, pair in
            let (namespace, namespaceTypes) = pair
            if namespace.isEmpty {
                return nodeRenderer.render(types: namespaceTypes)
            }
            return "  subgraph cluster_ns_\(index) {\n"
                + clusterOpen(label: namespace.dotEscaped)
                + nodeRenderer.render(types: namespaceTypes)
                + "  }\n\n"
        }.joined()
    }

    func renderByDirectory(types: [TypeDeclaration], directoryGroups: [String: [String]]) -> String {
        let nodeRenderer = DOTNodeRenderer(options: options)
        let typeIndex = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })

        return directoryGroups.sorted(by: { $0.key < $1.key }).enumerated().map { index, pair in
            let (dir, typeIds) = pair
            let clusterTypes = typeIds.compactMap { typeIndex[$0] }
            guard !clusterTypes.isEmpty else { return "" }
            let label = (dir.isEmpty ? "root" : dir).dotEscaped
            return "  subgraph cluster_dir_\(index) {\n"
                + clusterOpen(label: label)
                + nodeRenderer.render(types: clusterTypes)
                + "  }\n\n"
        }.joined()
    }

    /// The cluster's opening attribute lines. `color`/`fontcolor` are cosmetic, so they are only
    /// emitted when a theme is set — structural output leaves cluster colouring to the consumer.
    private func clusterOpen(label: String) -> String {
        var out = "    label=\"\(label)\";\n    style=rounded;\n"
        if let theme = options.theme {
            out += "    color=\"\(theme.nodeBorderColor)\";\n    fontcolor=\"\(theme.fontColor)\";\n"
        }
        return out
    }
}
