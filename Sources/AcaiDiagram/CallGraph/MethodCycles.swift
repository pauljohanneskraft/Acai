import AcaiCore

/// Method-level call cycles: the strongly-connected components of the call graph, i.e. clusters of
/// methods that (directly or transitively) call each other — mutual recursion or tangled method
/// clusters. A value you instantiate over an artifact (`MethodCycles(artifact:).clusters`); each
/// member carries its `file:line`. Reuses `StronglyConnectedComponents` over the call-graph edges.
public struct MethodCycles: Sendable {
    /// One method participating in a cycle.
    public struct Method: Codable, Hashable, Sendable {
        public var id: String
        public var location: SourceLocation?
    }

    /// A cluster of mutually-reachable methods.
    public struct Cluster: Codable, Hashable, Sendable {
        public var methods: [Method]
    }

    private let artifact: CodeArtifact
    private let scope: CallGraphScope

    public init(artifact: CodeArtifact, scope: CallGraphScope = .wholeCodebase) {
        self.artifact = artifact
        self.scope = scope
    }

    /// Every non-trivial call cycle, each a cluster of methods sorted by id; clusters are ordered by
    /// their first member for deterministic output.
    public var clusters: [Cluster] {
        let graph = CallGraphBuilder(scope: scope).build(from: artifact)
        let locations = MethodLocationIndex(artifact: artifact)

        var adjacency: [String: Set<String>] = [:]
        for edge in graph.edges {
            adjacency[edge.from, default: []].insert(edge.to)
        }

        return StronglyConnectedComponents(adjacency: adjacency).cycles
            .map { component in
                Cluster(methods: component.sorted().map { id in
                    Method(id: id, location: locations.location(forNodeID: id))
                })
            }
            .sorted { ($0.methods.first?.id ?? "") < ($1.methods.first?.id ?? "") }
    }
}
