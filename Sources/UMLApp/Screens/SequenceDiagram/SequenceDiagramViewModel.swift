import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender

/// Backs the movement-only sequence diagram view. The `SequenceDiagram` is regenerated from the
/// stored entry-point configuration (so it tracks the code), while the user may slide participant
/// lifelines horizontally; those offsets are the only editable, undoable state. Conforms to
/// `CanvasInteraction` so it reuses the shared canvas (pan/zoom, drag, marquee, undo/redo).
@MainActor
final class SequenceDiagramViewModel: ObservableObject, DiagramHistoryHosting, CanvasInteraction {
    let artifact: CodeArtifact

    @Published private(set) var diagram: SequenceDiagram
    /// Per-participant horizontal-centre overrides, keyed by `Participant.id`.
    @Published var participantOffsets: [String: CGFloat] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    private(set) var configuration: SequenceDiagramConfiguration

    // MARK: - Undo / Redo

    let history = DiagramHistoryManager<[String: CGFloat]>()

    /// Undoable state: the participant offsets. Persistence is the view's responsibility (it owns
    /// the canvas scale/offset), mirroring the class view model.
    var historySnapshot: [String: CGFloat] {
        get { participantOffsets }
        set { participantOffsets = newValue }
    }

    // MARK: - Init

    init(
        artifact: CodeArtifact,
        configuration: SequenceDiagramConfiguration,
        restoredOffsets: [String: CGFloat] = [:]
    ) {
        self.artifact = artifact
        self.configuration = configuration
        self.participantOffsets = restoredOffsets
        self.diagram = Self.generate(artifact: artifact, configuration: configuration)
    }

    private static func generate(
        artifact: CodeArtifact,
        configuration: SequenceDiagramConfiguration
    ) -> SequenceDiagram {
        artifact.sequenceDiagram(
            entryPoint: (configuration.entryTypeName, configuration.entryMethodName),
            maxDepth: configuration.maxDepth,
            typeMapping: configuration.typeMapping
        )
    }

    /// Re-runs the trace for a new configuration, dropping stale offsets and history.
    func applyConfiguration(_ newConfiguration: SequenceDiagramConfiguration) {
        configuration = newConfiguration
        diagram = Self.generate(artifact: artifact, configuration: newConfiguration)
        participantOffsets = [:]
        selectedNodeIDs = []
        history.clear()
    }

    var isEmpty: Bool { diagram.participants.isEmpty }

    // MARK: - Layout

    /// Current geometry, honouring participant drags.
    var layout: SequenceLayoutModel {
        SequenceLayoutModel(diagram: diagram, positionOverrides: participantOffsets)
    }

    private var frameByID: [String: SequenceLayoutModel.ParticipantFrame] {
        Dictionary(layout.participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - CanvasInteraction

    func nodePosition(_ id: String) -> CGPoint? {
        guard let frame = frameByID[id] else { return nil }
        return CGPoint(x: frame.lifelineX, y: frame.headerRect.midY)
    }

    /// Move a participant — horizontal only (the vertical position is fixed to the header row).
    func moveNode(_ id: String, to position: CGPoint) {
        participantOffsets[id] = position.x
    }

    func effectiveSize(for id: String) -> CGSize {
        frameByID[id]?.headerRect.size ?? CGSize(width: 120, height: SequenceLayoutModel.headerHeight)
    }

    /// Participants are fixed-size; resizing is a no-op.
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
            layout.participants
                .filter { rect.contains(CGPoint(x: $0.lifelineX, y: $0.headerRect.midY)) }
                .map(\.id)
        )
    }

    func clearSelection() { selectedNodeIDs.removeAll() }

    func selectAll() { selectedNodeIDs = Set(layout.participants.map(\.id)) }

    // MARK: - Image Export

    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        try DiagramImageRenderer.renderPNG(
            sequenceDiagram: diagram,
            positionOverrides: participantOffsets,
            scale: scale
        )
    }
}
