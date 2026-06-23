import UMLCore

extension CodeArtifact {

    /// Derives a `PackageDependencyDiagram` from this artifact.
    ///
    /// Types are grouped into build modules via `ModuleResolver.standard.productName(forFilePath:)`
    /// (one node per module). Every relationship whose endpoints live in different
    /// modules contributes to a weighted module→module edge; each distinct
    /// (source type → target type) crossing is counted once. Node metrics come
    /// straight from `computeMetrics().modules`.
    ///
    /// Call on an `enriched()` artifact so relationship endpoints are resolved to
    /// type ids (matching the requirement of `computeMetrics()`).
    public func packageDependencyDiagram(title: String? = nil) -> PackageDependencyDiagram {
        let nodes = computeMetrics().modules.map { module in
            PackageDependencyDiagram.Node(
                id: module.name,
                name: module.name,
                typeCount: module.typeCount,
                afferentCoupling: module.afferentCoupling,
                efferentCoupling: module.efferentCoupling,
                instability: module.instability,
                abstractness: module.abstractness
            )
        }

        var idToModule: [String: String] = [:]
        for type in flattened() {
            idToModule[type.id] = ModuleResolver.standard.productName(forFilePath: type.location?.filePath ?? "")
        }

        struct Pair: Hashable { let from: String; let to: String }
        var weights: [Pair: Int] = [:]
        var seenCrossings: Set<String> = []
        for rel in relationships {
            guard
                let from = idToModule[rel.source],
                let to = idToModule[rel.target],
                from != to,
                seenCrossings.insert("\(rel.source)→\(rel.target)").inserted
            else { continue }
            weights[Pair(from: from, to: to), default: 0] += 1
        }

        let edges = weights
            .sorted { ($0.key.from, $0.key.to) < ($1.key.from, $1.key.to) }
            .map { PackageDependencyDiagram.Edge(from: $0.key.from, to: $0.key.to, weight: $0.value) }

        return PackageDependencyDiagram(title: title, nodes: nodes, edges: edges)
    }
}
