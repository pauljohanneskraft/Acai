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
final class StateDiagramViewModel: ObservableObject, DiagramHistoryHosting, CanvasInteraction {
    let artifact: CodeArtifact

    /// `nil` while unconfigured (legacy diagrams created before the config popup).
    @Published private(set) var result: Result<StateDiagram, StateDiagramAnalysisError>?
    /// Per-state centre overrides, keyed by state id.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    private(set) var configuration: StateDiagramConfiguration?

    // MARK: - Undo / Redo

    let history = DiagramHistoryManager<[String: CGPoint]>()

    /// Undoable state: the node positions. Persistence is the view's responsibility (it owns
    /// the canvas scale/offset), mirroring the sequence view model.
    var historySnapshot: [String: CGPoint] {
        get { positionOverrides }
        set { positionOverrides = newValue }
    }

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
            return .success(try artifact.resolvingExtensions().stateDiagram(configuration: configuration))
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

    // MARK: - CanvasInteraction

    func nodePosition(_ id: String) -> CGPoint? {
        guard let frame = layout.frame(for: id) else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    func moveNode(_ id: String, to position: CGPoint) {
        positionOverrides[id] = position
    }

    func effectiveSize(for id: String) -> CGSize {
        layout.frame(for: id)?.size ?? CGSize(width: 80, height: 40)
    }

    /// States are fixed-size; resizing is a no-op.
    func resizeNode(_ id: String, width: CGFloat, height: CGFloat) {}

    func selectNode(_ id: String, extending: Bool) {
        if extending {
            if selectedNodeIDs.contains(id) { selectedNodeIDs.remove(id) } else { selectedNodeIDs.insert(id) }
        } else {
            selectedNodeIDs = [id]
        }
    }

    func selectNodes(in rect: CGRect) {
        selectedNodeIDs = Set(
            layout.nodes
                .filter { rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
                .map(\.id)
        )
    }

    func clearSelection() { selectedNodeIDs.removeAll() }

    func selectAll() { selectedNodeIDs = Set(layout.nodes.map(\.id)) }

    // MARK: - Image Export

    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        guard let diagram else { throw DiagramImageRenderError.renderingFailed }
        return try DiagramImageRenderer.renderPNG(
            stateDiagram: diagram,
            positionOverrides: positionOverrides,
            scale: scale
        )
    }
}
