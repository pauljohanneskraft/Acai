import AcaiCore
import AcaiDiagram
import AcaiRender

/// Derives the guided route from measurements already taken: the codebase's metrics and its call graph.
struct GuidedRouteBuilder: Sendable {
    let artifact: CodeArtifact
    let metrics: CodeMetrics

    var stops: [GuidedRouteStop] {
        [entryPointStop, mostDependedUponStop, mostComplexStop].compactMap { $0 }
    }

    private var entryPointStop: GuidedRouteStop? {
        let graph = CallGraphBuilder().build(from: artifact)
        let callees = Set(graph.edges.map(\.to))
        let fanOut = Dictionary(graph.edges.map { ($0.from, 1) }, uniquingKeysWith: +)
        let root = graph.nodes
            .filter { $0.inScope && !callees.contains($0.id) && fanOut[$0.id, default: 0] > 0 }
            .max { lhs, rhs in
                let (left, right) = (fanOut[lhs.id, default: 0], fanOut[rhs.id, default: 0])
                return left != right ? left < right : lhs.id > rhs.id
            }
        guard let root else { return nil }
        let scope: CallGraphScope = root.typeName.isEmpty ? .wholeCodebase : .type(root.typeName)
        return GuidedRouteStop(kind: .entryPoint, subject: root.label, content: .callGraph(scope))
    }

    private var mostDependedUponStop: GuidedRouteStop? {
        guard let top = topType(by: \.fanIn) else { return nil }
        var configuration = ClassDiagramConfiguration()
        configuration.focus = FocusConfiguration(rootTypeName: top.id, direction: .dependents)
        return GuidedRouteStop(kind: .mostDependedUpon, subject: top.name, content: .classDiagram(configuration))
    }

    private var mostComplexStop: GuidedRouteStop? {
        guard let top = topType(by: \.maxCyclomaticComplexity) else { return nil }
        var configuration = ClassDiagramConfiguration()
        configuration.focus = FocusConfiguration(rootTypeName: top.id)
        return GuidedRouteStop(kind: .mostComplex, subject: top.name, content: .classDiagram(configuration))
    }

    /// Ties break alphabetically by name so the pick is deterministic; `nil` when nothing scores above zero.
    private func topType(by metric: KeyPath<CodeMetrics.TypeMetric, Int>) -> CodeMetrics.TypeMetric? {
        metrics.types
            .filter { $0[keyPath: metric] > 0 }
            .max { lhs, rhs in
                let (left, right) = (lhs[keyPath: metric], rhs[keyPath: metric])
                return left != right ? left < right : lhs.name > rhs.name
            }
    }
}
