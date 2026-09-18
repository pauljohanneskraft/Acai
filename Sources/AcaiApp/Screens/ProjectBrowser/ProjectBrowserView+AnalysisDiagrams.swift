import SwiftUI
import AcaiCore

extension ProjectBrowserView {
    /// Neither needs `deltaHosted` (Compare vs git) — a chart/scatter view has no "delta" concept
    /// the way a structural diagram does.
    @ViewBuilder
    func analysisDiagramDetail(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) -> some View {
        if diagram.type == .moduleCoupling {
            ModuleCouplingChartView(diagram: diagram, artifact: artifact)
        } else {
            HotspotChartView(diagram: diagram, artifact: artifact, codebase: codebase)
        }
    }
}
