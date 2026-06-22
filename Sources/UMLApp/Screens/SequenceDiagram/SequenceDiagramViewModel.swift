import Foundation
import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender

/// Backs the movement-only sequence diagram view. The `SequenceDiagram` is regenerated from the
/// stored entry-point configuration (so it tracks the code), while the user may slide participant
/// lifelines horizontally; those overrides are the only editable, undoable state. Conforms to
/// `LayoutBackedCanvas` so it reuses the shared canvas (pan/zoom, drag, marquee, undo/redo) — only
/// the `x` of each override matters (the layout pins lifelines to the header row).
@MainActor
final class SequenceDiagramViewModel: ObservableObject, LayoutBackedCanvas {
    let artifact: CodeArtifact

    @Published private(set) var diagram: SequenceDiagram
    /// Per-participant centre overrides, keyed by `Participant.id`. Only `x` is honoured.
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []

    private(set) var configuration: SequenceDiagramConfiguration

    let history = DiagramHistoryManager<[String: CGPoint]>()

    // MARK: - Init

    init(
        artifact: CodeArtifact,
        configuration: SequenceDiagramConfiguration,
        restoredPositions: [String: CGPoint] = [:]
    ) {
        self.artifact = artifact
        self.configuration = configuration
        // Lifelines move horizontally only; normalize any restored y (older saved data may carry a
        // non-zero one) to 0 so stored positions round-trip cleanly. See `moveNode`.
        self.positionOverrides = restoredPositions.mapValues { CGPoint(x: $0.x, y: 0) }
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
        positionOverrides = [:]
        selectedNodeIDs = []
        history.clear()
    }

    var isEmpty: Bool { diagram.participants.isEmpty }

    // MARK: - Layout

    /// Current geometry, honouring participant drags (only the horizontal component is used).
    var layout: SequenceLayoutModel {
        SequenceLayoutModel(diagram: diagram, positionOverrides: positionOverrides.mapValues(\.x))
    }

    private var frameByID: [String: SequenceLayoutModel.ParticipantFrame] {
        Dictionary(layout.participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - LayoutBackedCanvas

    var allNodeIDs: [String] { layout.participants.map(\.id) }

    func nodeFrame(_ id: String) -> CGRect? { frameByID[id]?.headerRect }

    var defaultNodeSize: CGSize { CGSize(width: 120, height: SequenceLayoutModel.headerHeight) }

    /// Lifelines slide horizontally only — pin the override's `y` to 0 so nothing meaningless is
    /// persisted (the layout ignores `y`, and the saved positions round-trip cleanly).
    func moveNode(_ id: String, to position: CGPoint) {
        positionOverrides[id] = CGPoint(x: position.x, y: 0)
    }

    // MARK: - Image Export

    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        try DiagramImageRenderer.renderPNG(
            sequenceDiagram: diagram,
            positionOverrides: positionOverrides.mapValues(\.x),
            scale: scale
        )
    }
}
