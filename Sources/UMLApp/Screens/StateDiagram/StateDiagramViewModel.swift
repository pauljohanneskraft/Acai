import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender

/// Backs the movement-only state diagram view. The `StateDiagram` is regenerated from the
/// stored variable configuration (so it tracks the code); analysis failures are surfaced as
/// a typed error rather than an empty canvas. The user may drag state nodes freely; those
/// positions are the only editable, undoable state. Conforms to `CanvasInteraction` so it
/// reuses the shared canvas (pan/zoom, drag, marquee, undo/redo).
@MainActor
final class StateDiagramViewModel: ObservableObject, LayoutBackedCanvas {
    let artifact: CodeArtifact

    /// `nil` while the diagram has no state-variable spec chosen yet.
    @Published private(set) var result: Result<StateDiagram, StateDiagramAnalysisError>?
    /// Per-state centre overrides, keyed by state id.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    private(set) var configuration: StateDiagramConfiguration?

    let history = DiagramHistoryManager<[String: CGPoint]>()

    // MARK: - Init

    init(
        artifact: CodeArtifact,
        configuration: StateDiagramConfiguration?,
        restoredPositions: [String: CGPoint] = [:]
    ) {
        self.artifact = artifact
        self.configuration = configuration
        self.positionOverrides = restoredPositions
        self.result = Self.generate(artifact: artifact, configuration: configuration)
    }

    private static func generate(
        artifact: CodeArtifact,
        configuration: StateDiagramConfiguration?
    ) -> Result<StateDiagram, StateDiagramAnalysisError>? {
        guard let configuration else { return nil }
        do {
            return .success(try StateDiagramBuilder(configuration: configuration)
                .build(from: artifact.resolvingExtensions()))
        } catch let error as StateDiagramAnalysisError {
            return .failure(error)
        } catch {
            // `stateDiagram(configuration:)` only throws `StateDiagramAnalysisError`,
            // so this is unreachable; trap it loudly in debug rather than reporting a
            // misleading "no assignments" failure if that contract ever changes.
            assertionFailure("unexpected state-diagram analysis error: \(error)")
            return .failure(.noAssignments(variableName: configuration.variableName))
        }
    }

    /// Re-runs the analysis for a new configuration, dropping stale positions and history.
    func applyConfiguration(_ newConfiguration: StateDiagramConfiguration) {
        configuration = newConfiguration
        result = Self.generate(artifact: artifact, configuration: newConfiguration)
        positionOverrides = [:]
        selectedNodeIDs = []
        history.clear()
    }

    /// The generated diagram, when the analysis succeeded.
    var diagram: StateDiagram? {
        if case .success(let diagram) = result { return diagram }
        return nil
    }

    /// The analysis failure, when there is one.
    var analysisError: StateDiagramAnalysisError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    // MARK: - Layout

    /// Current geometry, honouring node drags.
    var layout: StateLayoutModel {
        StateLayoutModel(diagram: diagram ?? StateDiagram(), positionOverrides: positionOverrides)
    }

    // MARK: - LayoutBackedCanvas

    var allNodeIDs: [String] { layout.nodes.map(\.id) }

    func nodeFrame(_ id: String) -> CGRect? { layout.frame(for: id) }

    var defaultNodeSize: CGSize { CGSize(width: 80, height: 40) }

    // MARK: - Image Export

    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        guard let diagram else { throw DiagramImageRenderError.renderingFailed }
        return try StateImageRenderer().renderPNG(
            stateDiagram: diagram,
            positionOverrides: positionOverrides,
            scale: scale
        )
    }
}
