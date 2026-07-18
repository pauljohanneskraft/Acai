import AcaiCore

/// Finds dependency cycles in a `CodeArtifact`, at module or type scope, over the same graph the
/// quality rules see. Module adjacency is provenance-aware (via `ModuleAttribution`), so a
/// cross-module extension does not manufacture a phantom upward edge / false cycle.
///
/// Shared by `QualityEvaluator` (the `cycle` rule) and the `quality --explore` cycle listing so the
/// two never disagree.
public struct CycleFinder: Sendable {
    public enum Scope: String, Sendable, CaseIterable {
        case modules
        case types
    }

    /// One detected cycle: the strongly-connected component's members, sorted for determinism.
    public struct Cycle: Sendable, Equatable {
        public var scope: Scope
        public var members: [String]

        /// `A → B → C → A`-style rendering of the cycle.
        public var description: String {
            (members + [members.first].compactMap { $0 }).joined(separator: " → ")
        }
    }

    private let graph: GraphView
    private let attribution: ModuleAttribution

    public init(graph: GraphView, moduleResolver: ModuleResolver = .standard) {
        self.graph = graph
        let idToModule = Dictionary(graph.nodes.map { ($0.id, $0.module) }, uniquingKeysWith: { first, _ in first })
        self.attribution = ModuleAttribution(resolver: moduleResolver, idToModule: idToModule)
    }

    public init(
        artifact: CodeArtifact,
        moduleResolver: ModuleResolver = .standard,
        languageResolver: LanguageConfigurationResolver
    ) {
        self.init(
            graph: GraphView(
                artifact: artifact, moduleResolver: moduleResolver, languageResolver: languageResolver),
            moduleResolver: moduleResolver)
    }

    public func cycles(scope: Scope) -> [Cycle] {
        switch scope {
        case .modules:
            return components(adjacency: moduleAdjacency, scope: .modules)
        case .types:
            return components(adjacency: typeAdjacency, scope: .types)
        }
    }

    private var typeAdjacency: [String: Set<String>] {
        var adjacency: [String: Set<String>] = [:]
        for edge in graph.relationships {
            guard graph.node(id: edge.source) != nil, graph.node(id: edge.target) != nil,
                  edge.source != edge.target else { continue }
            adjacency[edge.source, default: []].insert(edge.target)
        }
        return adjacency
    }

    private var moduleAdjacency: [String: Set<String>] {
        var adjacency: [String: Set<String>] = [:]
        for edge in graph.relationships {
            guard let sourceModule = attribution.sourceModule(of: edge),
                  let targetModule = attribution.targetModule(of: edge),
                  sourceModule != targetModule else { continue }
            adjacency[sourceModule, default: []].insert(targetModule)
        }
        return adjacency
    }

    private func components(adjacency: [String: Set<String>], scope: Scope) -> [Cycle] {
        StronglyConnectedComponents(adjacency: adjacency).cycles
            .map { Cycle(scope: scope, members: $0.sorted()) }
            .sorted { $0.members.lexicographicallyPrecedes($1.members) }
    }
}
