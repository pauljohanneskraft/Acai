import SwiftUI
import AcaiCore

// Module Coupling/Cycle Diagram/Hotspot view routing, split out of `ProjectBrowserView.swift`'s
// `generatedDiagramDetail` purely to stay under SwiftLint's `function_body_length`/`file_length`
// limits — same rationale as `+Repositories.swift`.
extension ProjectBrowserView {
    /// Routes to whichever of the three read-only analysis-diagram views matches `diagram.type`.
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
            // `.cycleDiagram` — the only remaining case this is ever called with (see
            // `ProjectBrowserView.generatedDiagramDetail`'s call site).
            CycleDiagramView(diagram: diagram, artifact: artifact, codebase: codebase)
        }
    }
}
