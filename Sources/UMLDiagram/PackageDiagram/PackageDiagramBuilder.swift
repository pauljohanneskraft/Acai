import UMLCore

/// Builds a `PackageDiagram` (one node per build module) from a `CodeArtifact`.
///
/// Types are grouped into build modules via `ModuleResolver.standard`. Every relationship whose
/// endpoints live in different modules contributes to a weighted module→module edge (each distinct
/// source-type → target-type crossing counted once); node metrics come from `computeMetrics().modules`.
/// Edge source attribution is provenance-aware (`ModuleAttribution`), so a cross-module extension is
/// attributed to the extension's module rather than fabricating a phantom upward edge.
///
/// A value you instantiate with the options and ask to `build(from:)` — kept off `CodeArtifact` so the
/// data model does not depend on the diagram layer. Build from an `enriched()` artifact so endpoints
/// are resolved to type ids (as `computeMetrics()` requires).
public struct PackageDiagramBuilder: Sendable {
    public var title: String?

    public init(title: String? = nil) {
        self.title = title
    }

    public func build(from artifact: CodeArtifact) -> PackageDiagram {
        let nodes = artifact.computeMetrics().modules.map { module in
            PackageDiagram.Node(
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
        for type in artifact.flattened() {
            idToModule[type.id] = ModuleResolver.standard.productName(forFilePath: type.location?.filePath ?? "")
        }
        let attribution = ModuleAttribution(idToModule: idToModule)

        struct Pair: Hashable { let from: String; let to: String }
        var weights: [Pair: Int] = [:]
        var seenCrossings: Set<String> = []
        for rel in artifact.relationships {
            guard
                let from = attribution.sourceModule(of: rel),
                let to = attribution.targetModule(of: rel),
                from != to,
                seenCrossings.insert("\(rel.source)→\(rel.target)").inserted
            else { continue }
            weights[Pair(from: from, to: to), default: 0] += 1
        }

        let edges = weights
            .sorted { ($0.key.from, $0.key.to) < ($1.key.from, $1.key.to) }
            .map { PackageDiagram.Edge(from: $0.key.from, to: $0.key.to, weight: $0.value) }

        return PackageDiagram(title: title, nodes: nodes, edges: edges)
    }
}
