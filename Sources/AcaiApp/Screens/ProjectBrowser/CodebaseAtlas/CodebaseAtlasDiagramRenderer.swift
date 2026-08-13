import AcaiCore
import AcaiDiagram
import AcaiRender
import CoreGraphics
import Foundation

/// How one diagram's Atlas page turned out — always exactly one outcome per diagram, so the Atlas's
/// page count never depends on whether rendering happened to succeed.
enum AtlasDiagramRenderOutcome {
    case rendered(Data)
    /// No diagram kind here has an established PNG-export path — matches every other diagram kind's
    /// own "Export Image" action, which likewise only exists for the five kinds below.
    case unsupported
    case failed(any Error)
}

/// Resolves one `GeneratedDiagram` to its rendered PNG bytes via the same per-kind view models the
/// app's own "Export Image" action already uses (`ClassDiagramViewModel`, `SequenceDiagramViewModel`,
/// `StateDiagramViewModel`, `PackageDiagramViewModel`, `CallGraphViewModel` — see
/// `ProjectBrowserViewModel+Export.swift`'s `DiagramImageExporting` conformances). Reuses that
/// existing rendering pipeline rather than adding a new one; a value you instantiate over one
/// codebase and call `render(_:scale:)` on for each of its diagrams.
///
/// `moduleCoupling`/`hotspot`/`cycleDiagram` diagrams have no PNG-export path anywhere in the app
/// today (no per-diagram "Export Image" action covers them either — they're chart-style views, not
/// canvas-based diagrams with a `DiagramLayoutModel`), so they resolve to `.unsupported` rather than
/// growing a new renderer here.
@MainActor
struct CodebaseAtlasDiagramRenderer {
    let codebase: Codebase
    let artifact: CodeArtifact

    func render(_ diagram: GeneratedDiagram, scale: CGFloat) -> AtlasDiagramRenderOutcome {
        guard let exporter = imageExporter(for: diagram) else { return .unsupported }
        do {
            return .rendered(try exporter.exportPNGData(scale: scale))
        } catch {
            return .failed(error)
        }
    }

    private func imageExporter(for diagram: GeneratedDiagram) -> (any DiagramImageExporting)? {
        switch diagram.type {
        case .classDiagram:
            return ClassDiagramViewModel(
                codebase: codebase, artifact: artifact,
                configuration: diagram.classConfiguration ?? .init(),
                restoredPositions: diagram.nodePositions.mapValues(\.cgPoint),
                restoredSizes: diagram.nodeSizes.mapValues(\.cgSize))
        case .sequenceDiagram:
            return SequenceDiagramViewModel(
                artifact: artifact,
                configuration: diagram.sequenceConfiguration
                    ?? SequenceDiagramConfiguration(entryTypeName: "", entryMethodName: ""),
                restoredPositions: diagram.nodePositions.mapValues(\.cgPoint))
        case .stateDiagram:
            return StateDiagramViewModel(
                artifact: artifact, configuration: diagram.stateConfiguration,
                restoredPositions: diagram.nodePositions.mapValues(\.cgPoint))
        case .packageDiagram:
            return PackageDiagramViewModel(
                artifact: artifact, restoredPositions: diagram.nodePositions.mapValues(\.cgPoint))
        case .callGraph:
            return CallGraphViewModel(
                artifact: artifact, scope: diagram.callGraphScope ?? .wholeCodebase,
                restoredPositions: diagram.nodePositions.mapValues(\.cgPoint))
        case .moduleCoupling, .hotspot, .cycleDiagram:
            return nil
        }
    }
}
