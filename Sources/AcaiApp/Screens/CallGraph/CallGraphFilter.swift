import AcaiCore
import AcaiDiagram
import AcaiLibrary
import AcaiQuality

struct CallGraphFilter {
    let artifact: CodeArtifact
    let filter: AcaiQuality.Selector?

    /// Free functions and nodes whose type can't be resolved back to a declaration always pass
    /// through (fail open) rather than silently vanishing from the graph.
    func apply(to graph: CallGraph) -> CallGraph {
        guard let filter else { return graph }
        let graphView = GraphView(artifact: artifact, languageResolver: artifact.standardLanguageResolver)
        let typesByName = Dictionary(
            artifact.flattened().map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let keptIDs = Set(graph.nodes.filter { node in
            guard !node.typeName.isEmpty else { return true }
            guard let type = typesByName[node.typeName], let match = graphView.node(id: type.id) else { return true }
            return filter.matches(match)
        }.map(\.id))
        return CallGraph(
            title: graph.title,
            nodes: graph.nodes.filter { keptIDs.contains($0.id) },
            edges: graph.edges.filter { keptIDs.contains($0.from) && keptIDs.contains($0.to) },
            coverage: graph.coverage
        )
    }
}
