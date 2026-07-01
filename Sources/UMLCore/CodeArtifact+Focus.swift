// Single-class focus: reduce a class diagram to the subgraph around one type.
//
// `focusedSubset` is a pure graph operation over an already-resolved type/relationship
// set. It is the class-diagram counterpart of `SequenceDiagramConfiguration` — instead of
// tracing a call graph from an entry method, it walks the relationship graph from a root
// type and keeps only the reachable neighbourhood.

/// Restricts a class diagram to one type and the slice of the relationship graph around it.
///
/// The model is *source depends on target* for every `Relationship.Kind` (child → parent,
/// owner → owned, user → used), so following outgoing edges yields dependencies and
/// following incoming edges yields dependents.
public struct FocusConfiguration: Codable, Hashable, Sendable {
    /// Name (simple, qualified, or id) of the type the diagram is centred on.
    public var rootTypeName: String
    /// `nil` = unlimited; `1` = root + direct neighbours, `2` = + their neighbours, …
    public var maxDepth: Int?
    public var direction: Direction
    /// Edges of these kinds are followed during traversal *and* drawn. Defaults to all.
    public var includedRelationshipKinds: Set<Relationship.Kind>
    /// When `true`, every edge whose both endpoints landed in the selected set is drawn
    /// (still filtered by `includedRelationshipKinds`), not only the edges actually walked.
    public var includeInterconnections: Bool

    /// Which way the traversal walks the relationship graph from the root.
    public enum Direction: String, Codable, Hashable, Sendable, CaseIterable {
        /// Follow outgoing edges only — the types the root (transitively) depends on.
        case dependencies
        /// Follow incoming edges only — the types that (transitively) depend on the root.
        case dependents
        /// Run both walks independently from the root; a path never switches direction,
        /// so the node set is (dependencies-of-dependencies ∪ dependents-of-dependents).
        case both
    }

    public init(
        rootTypeName: String,
        maxDepth: Int? = nil,
        direction: Direction = .dependencies,
        includedRelationshipKinds: Set<Relationship.Kind> = Set(Relationship.Kind.allCases),
        includeInterconnections: Bool = true
    ) {
        self.rootTypeName = rootTypeName
        self.maxDepth = maxDepth
        self.direction = direction
        self.includedRelationshipKinds = includedRelationshipKinds
        self.includeInterconnections = includeInterconnections
    }
}

extension CodeArtifact {
    /// Returns the subset of `types`/`relationships` that falls within the focus.
    ///
    /// Endpoints are normalized to canonical type ids via `buildNameToId`, so this works
    /// whether or not the caller already resolved relationship names. An unresolvable root
    /// yields an empty subset.
    public static func focusedSubset(
        types: [TypeDeclaration],
        relationships: [Relationship],
        configuration: FocusConfiguration
    ) -> (types: [TypeDeclaration], relationships: [Relationship]) {
        let identity = TypeIdentityResolver(types: types)
        guard let rootId = identity.resolvedID(for: configuration.rootTypeName)?.value else {
            return (types: [], relationships: [])
        }
        let resolveId: (String) -> String = { identity.canonicalName(for: $0) }

        let traversal = FocusTraversal(
            relationships: relationships,
            resolveId: resolveId,
            allowedKinds: configuration.includedRelationshipKinds,
            maxDepth: configuration.maxDepth
        )
        let walk = traversal.walk(from: rootId, direction: configuration.direction)

        let keptRelationships = relationships.filter { rel in
            guard configuration.includedRelationshipKinds.contains(rel.kind) else { return false }
            let source = resolveId(rel.source)
            let target = resolveId(rel.target)
            if configuration.includeInterconnections {
                return walk.selected.contains(source) && walk.selected.contains(target)
            }
            return walk.usedPairs.contains("\(source)→\(target)")
        }

        return (types: filterTypes(types, keeping: walk.selected), relationships: keptRelationships)
    }

    /// Keeps types whose id is selected, preserving nesting — a parent is retained as a
    /// container when one of its nested types is selected even if the parent itself is not.
    private static func filterTypes(
        _ types: [TypeDeclaration], keeping selected: Set<String>
    ) -> [TypeDeclaration] {
        var result: [TypeDeclaration] = []
        for type in types {
            let keptNested = filterTypes(type.nestedTypes, keeping: selected)
            guard selected.contains(type.id) || !keptNested.isEmpty else { continue }
            var copy = type
            copy.nestedTypes = keptNested
            result.append(copy)
        }
        return result
    }
}

/// Walks the relationship graph from a root type, collecting the reachable nodes and the
/// edges actually traversed. `forward` adjacency yields dependencies, `backward` dependents;
/// a single walk never switches direction, so `.both` is the union of two independent walks.
private struct FocusTraversal {
    private let forward: [String: [String]]
    private let backward: [String: [String]]
    private let maxDepth: Int?

    init(
        relationships: [Relationship],
        resolveId: (String) -> String,
        allowedKinds: Set<Relationship.Kind>,
        maxDepth: Int?
    ) {
        var forward: [String: [String]] = [:]
        var backward: [String: [String]] = [:]
        for rel in relationships where allowedKinds.contains(rel.kind) {
            let source = resolveId(rel.source)
            let target = resolveId(rel.target)
            forward[source, default: []].append(target)
            backward[target, default: []].append(source)
        }
        self.forward = forward
        self.backward = backward
        self.maxDepth = maxDepth
    }

    func walk(
        from rootId: String, direction: FocusConfiguration.Direction
    ) -> (selected: Set<String>, usedPairs: Set<String>) {
        var selected: Set<String> = [rootId]
        var usedPairs: Set<String> = []
        if direction == .dependencies || direction == .both {
            bfs(from: rootId, useForward: true, selected: &selected, usedPairs: &usedPairs)
        }
        if direction == .dependents || direction == .both {
            bfs(from: rootId, useForward: false, selected: &selected, usedPairs: &usedPairs)
        }
        return (selected, usedPairs)
    }

    private func bfs(
        from rootId: String, useForward: Bool,
        selected: inout Set<String>, usedPairs: inout Set<String>
    ) {
        let adjacency = useForward ? forward : backward
        var visited: Set<String> = [rootId]
        var frontier: [String] = [rootId]
        var depth = 0
        while !frontier.isEmpty {
            if let max = maxDepth, depth >= max { break }
            var next: [String] = []
            for node in frontier {
                for neighbor in adjacency[node] ?? [] {
                    // Record the underlying edge oriented source → target.
                    usedPairs.insert(useForward ? "\(node)→\(neighbor)" : "\(neighbor)→\(node)")
                    if visited.insert(neighbor).inserted { next.append(neighbor) }
                }
            }
            frontier = next
            depth += 1
        }
        selected.formUnion(visited)
    }
}
