import Foundation
import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiLibrary
import AcaiQuality
import AcaiRender

/// Builds a `SequenceDiagram` from an entry-point trace, then applies the configuration's
/// `Selector` filter if any — an instantiated value with instance methods (never a static-function
/// namespace) that `SequenceDiagramViewModel` delegates diagram generation to, including from its
/// own `init`, before `self` is fully initialized and so before any of the view model's own
/// instance methods could be called.
private struct SequenceDiagramGenerator {
    let artifact: CodeArtifact
    let configuration: SequenceDiagramConfiguration

    func generate() -> SequenceDiagram {
        let diagram = SequenceDiagramBuilder(
            entryPoint: (configuration.entryTypeName, configuration.entryMethodName),
            maxDepth: configuration.maxDepth,
            typeMapping: configuration.typeMapping
        ).build(from: artifact)
        guard let filter = configuration.filter else { return diagram }
        return filtered(diagram, by: filter)
    }

    /// Drops participants `filter` doesn't match (and messages touching them) — except the trace's
    /// entry-point participant (always the first one added, per `SequenceDiagramBuilder`), which
    /// stays regardless: hiding the root of the trace would defeat the diagram's purpose. A free
    /// function, or a participant whose type can't be resolved back to a declaration, has no type to
    /// match a selector's module/stereotype/kind/access facets against, so it passes through
    /// (fails open) rather than silently vanishing.
    private func filtered(_ diagram: SequenceDiagram, by filter: AcaiQuality.Selector) -> SequenceDiagram {
        let entryID = diagram.participants.first?.id
        let graphView = GraphView(artifact: artifact, languageResolver: artifact.standardLanguageResolver)
        let typesByName = Dictionary(
            artifact.flattened().map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let keptIDs = Set(diagram.participants.filter { participant in
            guard participant.id != entryID else { return true }
            guard let type = typesByName[participant.name], let node = graphView.node(id: type.id) else {
                return true
            }
            return filter.matches(node)
        }.map(\.id))
        return SequenceDiagram(
            title: diagram.title,
            participants: diagram.participants.filter { keptIDs.contains($0.id) },
            messages: diagram.messages.filter { keptIDs.contains($0.from) && keptIDs.contains($0.to) },
            fragments: diagram.fragments
        )
    }
}

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
    @Published var isMultiSelectActive = false
    /// The selected message, keyed by its `SequenceLayoutModel.MessageLayout.id` (a positional index
    /// into the time-ordered message list, not a stable identity) — the Inspector tab. Positional
    /// ids are fine here: `applyConfiguration` always clears this alongside the node selection, so a
    /// stale index can never survive a configuration change.
    @Published var selectedMessageID: Int?

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
        // Lifelines move horizontally only; `moveNode` already pins every override's `y` to 0, so
        // restored positions round-trip cleanly with no normalization needed here.
        self.positionOverrides = restoredPositions
        self.diagram = SequenceDiagramGenerator(artifact: artifact, configuration: configuration).generate()
    }

    /// Re-runs the trace for a new configuration, dropping stale offsets and history.
    func applyConfiguration(_ newConfiguration: SequenceDiagramConfiguration) {
        configuration = newConfiguration
        diagram = SequenceDiagramGenerator(artifact: artifact, configuration: newConfiguration).generate()
        positionOverrides = [:]
        selectedNodeIDs = []
        selectedMessageID = nil
        history.clear()
    }

    /// Re-derives the diagram for a new filter, keeping the trace's entry point and — unlike
    /// `applyConfiguration` — the lifeline offsets/undo history, since filtering only removes
    /// participants/messages, it never repositions a surviving one.
    func applyFilter(_ filter: AcaiQuality.Selector?) {
        configuration.filter = filter
        diagram = SequenceDiagramGenerator(artifact: artifact, configuration: configuration).generate()
    }

    var isEmpty: Bool { diagram.participants.isEmpty }

    /// Clears the selected message whenever the participant selection is replaced (a secondary
    /// selection, same rationale as `FreeformDiagramViewModel.selectedEdgeID`).
    func selectionWillReplace() {
        selectedMessageID = nil
    }

    // MARK: - Layout

    /// Current geometry, honouring participant drags (only the horizontal component is used).
    var layout: SequenceLayoutModel {
        SequenceLayoutModel(diagram: diagram, positionOverrides: positionOverrides.mapValues(\.x))
    }

    private var frameByID: [String: SequenceLayoutModel.ParticipantFrame] {
        Dictionary(layout.participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The time-ordered messages, in the same order `SequenceLayoutModel.MessageLayout.id` indexes
    /// into — the source-of-truth lookup the Inspector tab resolves a selected message against.
    var orderedMessages: [SequenceDiagram.Message] { diagram.messages.sorted { $0.order < $1.order } }

    /// A participant's display name, or `nil` if it no longer exists (stale selection after a
    /// configuration change, which always clears the selection anyway).
    func participantName(_ id: String) -> String? {
        diagram.participants.first { $0.id == id }?.name
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
        try SequenceImageRenderer().renderPNG(
            sequenceDiagram: diagram,
            positionOverrides: positionOverrides.mapValues(\.x),
            context: RenderingContext(scale: scale)
        )
    }
}
