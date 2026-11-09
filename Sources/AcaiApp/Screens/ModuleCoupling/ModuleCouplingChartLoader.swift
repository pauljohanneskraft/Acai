import AcaiCore
import SwiftUI

/// Where the Module Coupling chart's data comes from. A protocol so a test can count computations
/// with a conformance of its own, injected into the loader it exercises rather than reached through
/// a shared instance.
protocol ModuleCouplingMetrics: Sendable {
    func chartData(of artifact: CodeArtifact) -> ModuleCouplingChartData
}

/// `CodeArtifact.computeMetrics(modules:)` over the artifact's own module map — a real walk of the
/// whole artifact (LCOM, feature envy, fan-in/out, …), which is why the loader keeps it off the
/// main actor.
struct ArtifactModuleCouplingMetrics: ModuleCouplingMetrics {
    func chartData(of artifact: CodeArtifact) -> ModuleCouplingChartData {
        let modules = ModuleMap(artifact: artifact)
        return ModuleCouplingChartData(
            modules: artifact.computeMetrics(modules: modules).modules,
            fallbackGroup: modules.resolver.fallbackGroup)
    }
}

/// Holds the Module Coupling chart's data across the chart view's re-creations. The view is built
/// fresh on every parent update, so computing in its `init` walked the whole artifact on the main
/// actor for every unrelated store change; living in `@State` instead, this computes once per
/// analysis identity, off the main actor, and a request for an identity it already holds — or is
/// already computing — does nothing.
@MainActor
@Observable
final class ModuleCouplingChartLoader {
    private(set) var data: ModuleCouplingChartData?

    private let metrics: any ModuleCouplingMetrics
    private var computing: ProjectBrowserViewModel.AnalysisToken?
    private var computed: ProjectBrowserViewModel.AnalysisToken?

    var isComputing: Bool { computing != nil }

    init(metrics: any ModuleCouplingMetrics = ArtifactModuleCouplingMetrics()) {
        self.metrics = metrics
    }

    func load(identity: ProjectBrowserViewModel.AnalysisToken, of artifact: CodeArtifact) async {
        guard computed != identity, computing != identity else { return }
        computing = identity
        defer { computing = nil }
        let metrics = metrics
        let work = Task.detached(priority: .userInitiated) { metrics.chartData(of: artifact) }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        data = result
        computed = identity
    }
}
