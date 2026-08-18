import AcaiCore
import AcaiQuality

/// Resolves a `CycleDiagramReference` (one detected `AcaiQuality.CycleFinder` cycle) against
/// an artifact into the nodes/edges a loop layout renders. No new detection logic — `CycleFinder`
/// already found *which* members form the cycle; this only resolves display edges among that
/// already-known member set and friendly labels, both purely rendering concerns.
struct CycleDiagramData {
    struct Node: Identifiable, Equatable {
        let id: String
        let label: String
    }

    struct Edge: Identifiable, Equatable {
        let id: String
        let from: String
        let to: String
    }

    let scope: CycleFinder.Scope
    let nodes: [Node]
    let edges: [Edge]

    init(reference: CycleDiagramReference, artifact: CodeArtifact) {
        let resolvedScope = CycleFinder.Scope(rawValue: reference.scope) ?? .types
        scope = resolvedScope
        let resolver = CycleEdgeResolver(members: Set(reference.members), artifact: artifact)
        switch resolvedScope {
        case .modules:
            edges = resolver.moduleScopeEdges
            nodes = reference.members.map { Node(id: $0, label: $0) }
        case .types:
            edges = resolver.typeScopeEdges
            let nameByID = resolver.typeNamesByID
            nodes = reference.members.map { Node(id: $0, label: nameByID[$0] ?? $0) }
        }
    }
}

/// Resolves the display edges among an already-known cycle-member set — a real value (constructed
/// with the member set and artifact it needs), not a static-function namespace, so the module- and
/// type-scope variants are instance-computed properties.
private struct CycleEdgeResolver {
    let members: Set<String>
    let artifact: CodeArtifact

    var typeNamesByID: [String: String] {
        Dictionary(artifact.flattened().map { ($0.id, $0.qualifiedName) }, uniquingKeysWith: { first, _ in first })
    }

    /// Edges among a `.types`-scope cycle's members: any relationship whose source and target are
    /// both members (excluding self-loops), deduplicated by source→target.
    var typeScopeEdges: [CycleDiagramData.Edge] {
        var seen = Set<String>()
        var result: [CycleDiagramData.Edge] = []
        for relationship in artifact.relationships {
            guard relationship.source != relationship.target,
                  members.contains(relationship.source), members.contains(relationship.target) else { continue }
            let key = "\(relationship.source)->\(relationship.target)"
            guard seen.insert(key).inserted else { continue }
            result.append(CycleDiagramData.Edge(id: key, from: relationship.source, to: relationship.target))
        }
        return result
    }

    /// Edges among a `.modules`-scope cycle's members: every type-level relationship whose two
    /// endpoints resolve (via `ModuleResolver.standard`, matching how `CodeMetrics`/`CycleFinder`
    /// themselves resolve a type to its module) to two different member modules, deduplicated by
    /// source-module→target-module.
    var moduleScopeEdges: [CycleDiagramData.Edge] {
        let moduleByID = Dictionary(
            artifact.flattened().map { type in
                (type.id, ModuleResolver.standard.productName(forFilePath: type.location?.filePath ?? ""))
            },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        var result: [CycleDiagramData.Edge] = []
        for relationship in artifact.relationships {
            guard let sourceModule = moduleByID[relationship.source],
                  let targetModule = moduleByID[relationship.target],
                  sourceModule != targetModule,
                  members.contains(sourceModule), members.contains(targetModule) else { continue }
            let key = "\(sourceModule)->\(targetModule)"
            guard seen.insert(key).inserted else { continue }
            result.append(CycleDiagramData.Edge(id: key, from: sourceModule, to: targetModule))
        }
        return result
    }
}
