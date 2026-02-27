import UMLCore

extension CodeArtifact {

    public enum DeploymentDiagramGranularity: String, Codable, Hashable, Sendable, CaseIterable {

    /// Each **source file** is a component node.
    ///
    /// Types in the same file share a node. Cross-file type references
    /// (present in `CodeArtifact.relationships`) produce communication paths
    /// between the corresponding file nodes.
    case fileLevel

    /// Each **namespace / package / module** is a component node.
    ///
    /// Types that share a `namespace` share a node. Types without a namespace
    /// fall into a root node named after the source language. Cross-namespace
    /// references produce communication paths.
    case packageLevel

    /// The entire `CodeArtifact` is a **single** component node.
    ///
    /// Useful when one `CodeArtifact` represents one deployable unit and you
    /// want to compose multiple artifacts externally to show inter-service
    /// communication.
    case artifactLevel
}


    /// Derives a `DeploymentDiagram` from this artifact.
    ///
    /// The `granularity` parameter controls how types are grouped into nodes:
    ///
    /// - `.fileLevel`: one node per source file; cross-file references → communication paths.
    /// - `.packageLevel` *(default)*: one node per namespace/package; cross-namespace
    ///   references → communication paths.
    /// - `.artifactLevel`: the entire artifact becomes a single node; combine multiple
    ///   `CodeArtifact` deploymentDiagrams externally to show inter-service topology.
    ///
    /// Communication paths are deduplicated — multiple references between the same
    /// pair of nodes produce exactly one path.
    public func deploymentDiagram(
        title: String? = nil,
        granularity: DeploymentDiagramGranularity = .packageLevel
    ) -> DeploymentDiagram {
        let (nodes, typeToNodeId) = buildDeploymentNodes(granularity: granularity)
        let paths = buildCommunicationPaths(typeToNodeId: typeToNodeId)
        return DeploymentDiagram(title: title, nodes: nodes, communicationPaths: paths)
    }

    // MARK: Node building

    private func buildDeploymentNodes(granularity: DeploymentDiagramGranularity)
        -> (nodes: [DeploymentDiagram.Node], typeToNodeId: [String: String]) {
        switch granularity {

        case .fileLevel:
            return groupedDeploymentNodes(
                kind: .executionEnvironment,
                keyOf: { type in
                    guard let path = type.location?.filePath else { return nil }
                    return path.split(separator: "/").last.map(String.init) ?? path
                }
            )

        case .packageLevel:
            return groupedDeploymentNodes(
                kind: .server,
                keyOf: { $0.namespace }
            )

        case .artifactLevel:
            let name = metadata.sourceLanguage.rawValue.capitalized
            let nodeId = "artifact"
            let node = DeploymentDiagram.Node(
                id: nodeId,
                name: name,
                kind: .device,
                artifacts: types.map(Self.deploymentArtifact(from:))
            )
            var map: [String: String] = [:]
            for t in types { map[t.id] = nodeId; map[t.name] = nodeId }
            return ([node], map)
        }
    }

    /// Generic grouping helper: groups types by a key derived from each `TypeDeclaration`.
    private func groupedDeploymentNodes(
        kind: DeploymentDiagram.Node.Kind,
        keyOf: (TypeDeclaration) -> String?
    ) -> (nodes: [DeploymentDiagram.Node], typeToNodeId: [String: String]) {

        var grouped: [String: [TypeDeclaration]] = [:]
        var ungrouped: [TypeDeclaration] = []
        for type in types {
            if let key = keyOf(type) { grouped[key, default: []].append(type) } else { ungrouped.append(type) }
        }

        var nodes: [DeploymentDiagram.Node] = []
        var map: [String: String] = [:]

        for (group, groupTypes) in grouped.sorted(by: { $0.key < $1.key }) {
            let nodeId = Self.safeId(group)
            nodes.append(DeploymentDiagram.Node(
                id: nodeId,
                name: group,
                kind: kind,
                artifacts: groupTypes.map(Self.deploymentArtifact(from:))
            ))
            for t in groupTypes { map[t.id] = nodeId; map[t.name] = nodeId }
        }

        if !ungrouped.isEmpty {
            let rootName = metadata.sourceLanguage.rawValue.capitalized
            let rootId = "root"
            nodes.insert(DeploymentDiagram.Node(
                id: rootId,
                name: rootName,
                kind: .device,
                artifacts: ungrouped.map(Self.deploymentArtifact(from:))
            ), at: 0)
            for t in ungrouped { map[t.id] = rootId; map[t.name] = rootId }
        }

        return (nodes, map)
    }

    // MARK: Communication path detection

    /// Scans `relationships` for cross-node references and returns deduplicated paths.
    private func buildCommunicationPaths(
        typeToNodeId: [String: String]
    ) -> [DeploymentDiagram.CommunicationPath] {
        var seen: Set<String> = []
        var paths: [DeploymentDiagram.CommunicationPath] = []
        for rel in relationships {
            guard
                let fromId = typeToNodeId[rel.source],
                let toId   = typeToNodeId[rel.target],
                fromId != toId,
                seen.insert("\(fromId)→\(toId)").inserted
            else { continue }
            paths.append(DeploymentDiagram.CommunicationPath(from: fromId, to: toId))
        }
        return paths
    }

    // MARK: Shared helpers

    internal static func safeId(_ s: String) -> String {
        s.map { c in (c.isLetter || c.isNumber) ? String(c) : "_" }.joined()
    }

    private static func deploymentArtifact(from type: TypeDeclaration) -> DeploymentDiagram.Artifact {
        DeploymentDiagram.Artifact(id: type.id, name: type.name, kind: deploymentArtifactKind(for: type.kind))
    }

    private static func deploymentArtifactKind(for kind: TypeKind) -> DeploymentDiagram.Artifact.Kind {
        switch kind {
        case .class, .object, .record:
            return .executable
        case .protocol, .interface, .trait:
            return .library
        case .struct:
            return .library
        case .enum:
            return .source
        case .typeAlias, .extension, .annotation, .module, .mixin:
            return .file
        }
    }
}