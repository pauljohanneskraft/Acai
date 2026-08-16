import SwiftUI
import AcaiCore

extension ProjectBrowserView {
    /// None of the three needs `deltaHosted` (Compare vs git) — a chart/scatter/isolated-cycle view
    /// has no "delta" concept the way a structural diagram does.
    @ViewBuilder
    func analysisDiagramDetail(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) -> some View {
        switch diagram.type {
        case .moduleCoupling:
            ModuleCouplingChartView(diagram: diagram, artifact: artifact, codebase: codebase)
        case .hotspot:
            HotspotChartView(diagram: diagram, artifact: artifact, codebase: codebase)
        default:
            // `.cycleDiagram` is the only remaining case this is ever called with.
            CycleDiagramView(diagram: diagram, artifact: artifact, codebase: codebase)
        }
    }
}
