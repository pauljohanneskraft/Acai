import AcaiCore

/// Per-method call-graph metrics — fan-in (callers), fan-out (callees), recursion, and the graph's
/// resolution coverage — as data rather than a diagram. A value you instantiate over an artifact
/// (`CallGraphMetrics(artifact:).report`); the CLI's `callgraph` command and downstream tooling
/// render it. Recursion is computed from strongly-connected components, so it catches both self-calls
/// and mutual recursion.
public struct CallGraphMetrics: Sendable {
    /// One method's call-graph position.
    public struct NodeMetric: Codable, Hashable, Sendable {
        public var id: String
        public var label: String
        /// Distinct methods that call this one.
        public var fanIn: Int
        /// Distinct methods this one calls.
        public var fanOut: Int
        /// Part of a call cycle (self-recursion or mutual recursion).
        public var isRecursive: Bool
        /// `false` for an out-of-scope callee pulled in only as a leaf.
        public var inScope: Bool
        public var location: SourceLocation?
    }

    /// The whole-graph metric report.
    public struct Report: Codable, Hashable, Sendable {
        public var coverage: CallGraph.Coverage
        public var nodeCount: Int
        public var edgeCount: Int
        /// Nodes ranked hottest first (by fan-in, then fan-out).
        public var nodes: [NodeMetric]
    }

    private let artifact: CodeArtifact
    private let scope: CallGraphScope
    private let title: String?

    public init(artifact: CodeArtifact, scope: CallGraphScope = .wholeCodebase, title: String? = nil) {
        self.artifact = artifact
        self.scope = scope
        self.title = title
    }

    public var report: Report {
        let graph = CallGraphBuilder(scope: scope, title: title).build(from: artifact)
        let locations = MethodLocationIndex(artifact: artifact)

        var fanIn: [String: Int] = [:]
        var fanOut: [String: Int] = [:]
        var adjacency: [String: Set<String>] = [:]
        for edge in graph.edges {
            fanOut[edge.from, default: 0] += 1
            fanIn[edge.to, default: 0] += 1
            adjacency[edge.from, default: []].insert(edge.to)
        }
        let recursive = Set(StronglyConnectedComponents(adjacency: adjacency).cycles.flatMap { $0 })

        let nodes = graph.nodes
            .map { node in
                NodeMetric(
                    id: node.id,
                    label: node.label,
                    fanIn: fanIn[node.id] ?? 0,
                    fanOut: fanOut[node.id] ?? 0,
                    isRecursive: recursive.contains(node.id),
                    inScope: node.inScope,
                    location: locations.location(forNodeID: node.id))
            }
            .sorted { lhs, rhs in
                if lhs.fanIn != rhs.fanIn { return lhs.fanIn > rhs.fanIn }
                if lhs.fanOut != rhs.fanOut { return lhs.fanOut > rhs.fanOut }
                return lhs.id < rhs.id
            }

        return Report(
            coverage: graph.coverage,
            nodeCount: graph.nodes.count,
            edgeCount: graph.edges.count,
            nodes: nodes)
    }
}
