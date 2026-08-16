import Foundation
import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiRender

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
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []
    @Published var isMultiSelectActive = false
    /// The selected transition, keyed by its position in `diagram.transitions` (also
    /// `StateLayoutModel.EdgeLayout.id`) — the Inspector tab. Positional, not a stable identity;
    /// safe because `applyConfiguration` always clears this alongside the node selection.
    @Published var selectedTransitionID: Int?

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

    func applyConfiguration(_ newConfiguration: StateDiagramConfiguration) {
        configuration = newConfiguration
        result = Self.generate(artifact: artifact, configuration: newConfiguration)
        positionOverrides = [:]
        selectedNodeIDs = []
        selectedTransitionID = nil
        history.clear()
    }

    /// Clears the selected transition whenever the state selection is replaced (a secondary
    /// selection, same rationale as `FreeformDiagramViewModel.selectedEdgeID`).
    func selectionWillReplace() {
        selectedTransitionID = nil
    }

    /// A state's display name, or `nil` if it no longer exists (stale selection after a
    /// configuration change, which always clears the selection anyway).
    func stateName(_ id: String) -> String? {
        diagram?.states.first { $0.id == id }?.name
    }

    var diagram: StateDiagram? {
        if case .success(let diagram) = result { return diagram }
        return nil
    }

    var analysisError: StateDiagramAnalysisError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    // MARK: - Layout

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
            context: RenderingContext(scale: scale)
        )
    }
}
