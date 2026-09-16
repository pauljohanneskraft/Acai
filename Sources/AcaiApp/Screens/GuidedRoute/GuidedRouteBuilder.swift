import Foundation
import AcaiCore
import AcaiDiagram
import AcaiRender

/// Builds a `GuidedRoute` purely from measurements a codebase's own analysis already computed —
/// `CodeMetrics` and a call graph built the same way the Call Graph diagram itself builds one. No
/// new analysis, per issue #199's "assembled entirely from measurements already taken".
struct GuidedRouteBuilder {
    let projectID: UUID
    let codebaseID: UUID
    let artifact: CodeArtifact
    let metrics: CodeMetrics

    /// `nil` when none of the three stops resolved to anything — a codebase too small or too
    /// disconnected to have a meaningful "where do I start".
    func build() -> GuidedRoute? {
        let stops = [entryPointStop(), mostDependedUponStop(), mostComplexStop()].compactMap { $0 }
        guard !stops.isEmpty else { return nil }
        return GuidedRoute(projectID: projectID, codebaseID: codebaseID, stops: stops)
    }

    /// A method nothing in the codebase calls, but that itself calls out — a call-graph root, and
    /// exactly where execution enters. `nil` when the call graph resolved no such root (e.g. an
    /// empty codebase, or one where every method has some caller).
    private func entryPointStop() -> GuidedRoute.Stop? {
        let nodes = CallGraphMetrics(artifact: artifact).report.nodes
        guard let root = nodes.first(where: { $0.inScope && $0.fanIn == 0 && $0.fanOut > 0 }) else { return nil }
        return GuidedRoute.Stop(kind: .entryPoint, subject: root.label, content: .callGraph(.wholeCodebase))
    }

    /// The type the most other types depend on, opened as a class diagram focused on its dependents.
    private func mostDependedUponStop() -> GuidedRoute.Stop? {
        guard let top = topType(by: { $0.fanIn }) else { return nil }
        var configuration = ClassDiagramConfiguration()
        configuration.focus = FocusConfiguration(rootTypeName: top.id, direction: .dependents)
        return GuidedRoute.Stop(kind: .mostDependedUpon, subject: top.name, content: .classDiagram(configuration))
    }

    /// The type carrying the single most complex method, opened as a class diagram focused on it.
    private func mostComplexStop() -> GuidedRoute.Stop? {
        guard let top = topType(by: { $0.maxCyclomaticComplexity }) else { return nil }
        var configuration = ClassDiagramConfiguration()
        configuration.focus = FocusConfiguration(rootTypeName: top.id)
        return GuidedRoute.Stop(kind: .mostComplex, subject: top.name, content: .classDiagram(configuration))
    }

    /// Highest-scoring type by `metric`, ties broken alphabetically by name for a deterministic
    /// pick. `nil` when nothing scores above zero.
    private func topType(by metric: (CodeMetrics.TypeMetric) -> Int) -> CodeMetrics.TypeMetric? {
        metrics.types
            .filter { metric($0) > 0 }
            .sorted { lhs, rhs in
                let (left, right) = (metric(lhs), metric(rhs))
                return left != right ? left > right : lhs.name < rhs.name
            }
            .first
    }
}
