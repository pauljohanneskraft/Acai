import UMLCore

/// Groups `TypeDeclaration` values into DOT subgraph clusters by file or namespace.
struct DOTClusterRenderer {
    let options: DiagramOptions

    func renderByFile(types: [TypeDeclaration]) -> String {
        let nodeRenderer = DOTNodeRenderer(options: options)
        let grouped = Dictionary(grouping: types) { $0.location?.filePath ?? "unknown" }
        return grouped.sorted(by: { $0.key < $1.key }).enumerated().map { index, pair in
            let (filePath, fileTypes) = pair
            let label = filePath.dotEscaped
            return """
              subgraph cluster_\(index) {
                label="\(label)";
                style=rounded;
                color="\(options.theme.nodeBorderColor)";
                fontcolor="\(options.theme.fontColor)";
            \(nodeRenderer.render(types: fileTypes))  }

            """
        }.joined()
    }

    func renderByNamespace(types: [TypeDeclaration]) -> String {
        let nodeRenderer = DOTNodeRenderer(options: options)
        let grouped = Dictionary(grouping: types) { $0.namespace ?? "" }
        return grouped.sorted(by: { $0.key < $1.key }).enumerated().map { index, pair in
            let (ns, nsTypes) = pair
            if ns.isEmpty {
                return nodeRenderer.render(types: nsTypes)
            }
            let label = ns.dotEscaped
            return """
              subgraph cluster_ns_\(index) {
                label="\(label)";
                style=rounded;
                color="\(options.theme.nodeBorderColor)";
                fontcolor="\(options.theme.fontColor)";
            \(nodeRenderer.render(types: nsTypes))  }

            """
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
            return """
              subgraph cluster_dir_\(index) {
                label="\(label)";
                style=rounded;
                color="\(options.theme.nodeBorderColor)";
                fontcolor="\(options.theme.fontColor)";
            \(nodeRenderer.render(types: clusterTypes))  }

            """
        }.joined()
    }
}
