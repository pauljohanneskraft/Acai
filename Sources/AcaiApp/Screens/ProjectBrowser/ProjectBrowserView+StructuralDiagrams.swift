import SwiftUI
import AcaiCore

extension ProjectBrowserView {
    /// The generated diagram types with a delta-comparison concept: each renders through
    /// `deltaHosted` so a compare-against-revision button and badge/colour overlay are available.
    @ViewBuilder
    func structuralDiagramDetail(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) -> some View {
        switch diagram.type {
        case .sequenceDiagram:
            deltaHosted(diagram: diagram) { isComparePresented in
                SequenceDiagramView(
                    diagram: diagram, artifact: artifact, codebase: codebase,
                    isComparePresented: isComparePresented,
                    comparisonArtifact: model.comparisonArtifact(for: diagram))
            }
        case .stateDiagram:
            deltaHosted(diagram: diagram) { isComparePresented in
                StateDiagramView(
                    diagram: diagram, artifact: artifact, codebase: codebase,
                    isComparePresented: isComparePresented,
                    comparisonArtifact: model.comparisonArtifact(for: diagram))
            }
        case .packageDiagram:
            deltaHosted(diagram: diagram) { isComparePresented in
                PackageDiagramView(
                    diagram: diagram, artifact: artifact, codebase: codebase,
                    isComparePresented: isComparePresented,
                    comparisonArtifact: model.comparisonArtifact(for: diagram))
            }
        case .callGraph:
            deltaHosted(diagram: diagram) { isComparePresented in
                CallGraphView(
                    diagram: diagram, artifact: artifact, codebase: codebase,
                    isComparePresented: isComparePresented,
                    comparisonArtifact: model.comparisonArtifact(for: diagram))
            }
        default:
            // `.classDiagram` (and any future default) is the only remaining case this is called with.
            deltaHosted(diagram: diagram) { isComparePresented in
                ClassDiagramView(
                    diagram: diagram, artifact: artifact, codebase: codebase,
                    isComparePresented: isComparePresented,
                    comparisonArtifact: model.comparisonArtifact(for: diagram))
            }
        }
    }
}
