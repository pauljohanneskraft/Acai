import AcaiCore
import AcaiQuality

/// Builds a `PackageDiagram` (one node per build module) from a `CodeArtifact`.
///
/// Types are grouped into build modules via `ModuleResolver.standard`. Every relationship whose
/// endpoints live in different modules contributes to a weighted module→module edge (each distinct
/// source-type → target-type crossing counted once); node metrics come from `computeMetrics().modules`.
/// Edge source attribution is provenance-aware (`ModuleAttribution`), so a cross-module extension is
/// attributed to the extension's module rather than fabricating a phantom upward edge.
///
/// A value you instantiate and ask to `build(from:)`. Build from an `enriched()` artifact so
/// endpoints are resolved to type ids (as `computeMetrics()` requires).
public struct PackageDiagramBuilder: Sendable {
    public var title: String?
    /// When set, only modules this selector matches (via `Selector.matchesModule(named:)` — the
    /// only facet that applies to a module node) are kept, along with edges between two kept
    /// modules. `nil` (the default) keeps every module.
    public var filter: AcaiQuality.Selector?

    public init(title: String? = nil, filter: AcaiQuality.Selector? = nil) {
        self.title = title
        self.filter = filter
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
                // Scope the dedup to the attributed module pair too: the same type pair can be
                // attributed to different module pairs (e.g. one edge from a cross-module extension
                // file, another from the type's home module), and each is a distinct module crossing.
                seenCrossings.insert("\(from)→\(to)::\(rel.source)→\(rel.target)").inserted
            else { continue }
            weights[Pair(from: from, to: to), default: 0] += 1
        }

        let edges = weights
            .sorted { ($0.key.from, $0.key.to) < ($1.key.from, $1.key.to) }
            .map { PackageDiagram.Edge(from: $0.key.from, to: $0.key.to, weight: $0.value) }

        guard let filter else { return PackageDiagram(title: title, nodes: nodes, edges: edges) }
        let keptNames = Set(nodes.filter { filter.matchesModule(named: $0.name) }.map(\.name))
        return PackageDiagram(
            title: title,
            nodes: nodes.filter { keptNames.contains($0.name) },
            edges: edges.filter { keptNames.contains($0.from) && keptNames.contains($0.to) }
        )
    }
}
