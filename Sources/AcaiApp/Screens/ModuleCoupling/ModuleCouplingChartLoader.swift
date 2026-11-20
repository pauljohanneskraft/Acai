import AcaiCore
import SwiftUI

protocol ModuleCouplingMetrics: Sendable {
    func chartData(of artifact: CodeArtifact) -> ModuleCouplingChartData
}

struct ArtifactModuleCouplingMetrics: ModuleCouplingMetrics {
    func chartData(of artifact: CodeArtifact) -> ModuleCouplingChartData {
        let modules = ModuleMap(artifact: artifact)
        return ModuleCouplingChartData(
            modules: artifact.computeMetrics(modules: modules).modules,
            fallbackGroup: modules.resolver.fallbackGroup)
    }
}

/// Everything that decides which artifact the chart is built from; a comparison only replaces the
/// live artifact once its revision has loaded, hence `showsComparisonArtifact`.
struct ModuleCouplingChartIdentity: Equatable {
    let analysis: ProjectBrowserViewModel.AnalysisToken
    let comparisonBaseRef: String?
    let comparisonGitRef: String?
    let showsComparisonArtifact: Bool
}

/// Lives in the chart view's `@State`, so the walk runs once per identity off the main actor rather
/// than on every re-creation of the view.
@MainActor
@Observable
final class ModuleCouplingChartLoader {
    private(set) var data: ModuleCouplingChartData?

    private let metrics: any ModuleCouplingMetrics
    private var computed: ModuleCouplingChartIdentity?
    private var inFlight: (identity: ModuleCouplingChartIdentity, work: Task<ModuleCouplingChartData, Never>)?

    var isComputing: Bool { inFlight != nil }

    init(metrics: any ModuleCouplingMetrics = ArtifactModuleCouplingMetrics()) {
        self.metrics = metrics
    }

    func load(identity: ModuleCouplingChartIdentity, of artifact: CodeArtifact) async {
        guard computed != identity else { return }
        let work: Task<ModuleCouplingChartData, Never>
        if let inFlight, inFlight.identity == identity {
            work = inFlight.work
        } else {
            inFlight?.work.cancel()
            data = nil
            computed = nil
            let metrics = metrics
            work = Task.detached(priority: .userInitiated) { metrics.chartData(of: artifact) }
            inFlight = (identity, work)
        }
        let result = await work.value
        guard inFlight?.identity == identity else { return }
        data = result
        computed = identity
        inFlight = nil
    }
}
