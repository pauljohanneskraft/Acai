import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiRender
import UniformTypeIdentifiers

/// Movement-only view for a generated sequence diagram. Regenerates the diagram from its stored
/// entry-point configuration and lets the user slide participant lifelines horizontally; built on
/// the shared canvas layer (`PannableCanvas`, drag gesture, undo/redo) like the class view.
struct SequenceDiagramView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: SequenceDiagramViewModel

    @State private var canvasScale: CGFloat
    @State private var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var showConfigSheet = false

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        let config = diagram.sequenceConfiguration
            ?? SequenceDiagramConfiguration(entryTypeName: "", entryMethodName: "")
        self._viewModel = StateObject(wrappedValue: SequenceDiagramViewModel(
            artifact: artifact,
            configuration: config,
            restoredPositions: diagram.nodePositions.mapValues { CGPoint(x: $0.x, y: $0.y) }
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                canvasContent
            }
        }
        .toolbar { toolbarContent }
        .diagramCanvasLifecycle(
            title: diagram.name, model: viewModel, onSave: savePositions, onCenter: centerDiagram
        )
        .sheet(isPresented: $showConfigSheet) {
            SequenceConfigSheet(
                artifact: artifact,
                initial: viewModel.configuration,
                onCancel: { showConfigSheet = false },
                onCreate: { config in
                    viewModel.applyConfiguration(config)
                    model.diagrams.updateSequenceConfiguration(diagramID: diagram.id, configuration: config)
                    showConfigSheet = false
                    centerDiagram()
                }
            )
        }
    }

    // MARK: - Canvas

    private var canvasContent: some View {
        PannableCanvas(
            model: viewModel,
            scale: $canvasScale,
            offset: $canvasOffset,
            activeDragCanvasLocation: activeDragCanvasLocation,
            autoPanController: canvasAutoPanController
        ) {
            let layout = viewModel.layout
            ZStack(alignment: .topLeading) {
                SequenceEnsembleView(layout: layout)
                ForEach(layout.participants) { participant in
                    participantHeader(participant)
                }
            }
        }
    }

    private func participantHeader(_ participant: SequenceLayoutModel.ParticipantFrame) -> some View {
        SequenceParticipantHeader(
            participant: participant,
            isSelected: viewModel.selectedNodeIDs.contains(participant.id)
        )
        .frame(width: participant.headerRect.width, height: participant.headerRect.height)
        .position(x: participant.headerRect.midX, y: participant.headerRect.midY)
        .diagramNodeInteraction(
            id: participant.id,
            model: viewModel,
            dragStartPositions: $dragStartPositions,
            activeDragCanvasLocation: $activeDragCanvasLocation,
            onCommit: savePositions
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            UndoRedoToolbarButtons(model: viewModel, onChange: savePositions)

            Button {
                centerDiagram()
            } label: {
                Label("Fit to View", systemImage: "rectangle.dashed")
            }
            .help("Fit the diagram to the visible canvas (⌘0)")
            .keyboardShortcut("0", modifiers: .command)
            Button {
                showConfigSheet = true
            } label: {
                Label("Edit Configuration", systemImage: "slider.horizontal.3")
            }
            .help("Change the sequence diagram's entry point and depth")
            Button {
                // Pass every participant's live x (not just dragged overrides) so the freeform
                // copy reproduces the current layout exactly.
                let layoutPositions = Dictionary(
                    viewModel.layout.participants.map { ($0.id, CGPoint(x: $0.lifelineX, y: 0)) },
                    uniquingKeysWith: { first, _ in first }
                )
                model.saveAsFreeformDiagram(
                    id: diagram.id,
                    positions: layoutPositions,
                    scale: canvasScale,
                    offset: canvasOffset
                )
            } label: {
                Label("Save as Freeform", systemImage: "document.on.document")
            }
            .help("Save a copy as an editable Freeform diagram")
            .disabled(viewModel.isEmpty)
            Button {
                exportImage()
            } label: {
                Label("Export Image", systemImage: "photo")
            }
            .help("Export the diagram as an image")
            .disabled(viewModel.isEmpty)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No calls could be traced from this entry point.")
                .foregroundStyle(.secondary)
            Text("Calls are followed through explicitly-typed property receivers; "
                 + "try a different starting method or resolve its interfaces.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                showConfigSheet = true
            } label: {
                Label("Edit Configuration", systemImage: "slider.horizontal.3")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Persistence & layout

    private func savePositions() {
        model.diagrams.updatePositions(
            diagramID: diagram.id,
            positions: viewModel.positionOverrides,
            scale: canvasScale,
            offset: canvasOffset
        )
    }

    private func centerDiagram() {
        guard let fit = FitToView(
            nodeIDs: viewModel.layout.participants.map(\.id),
            rect: { viewModel.nodeRect($0) }
        ).transform else { return }
        canvasScale = fit.scale
        canvasOffset = fit.offset
        savePositions()
    }

    private func exportImage() {
        model.exportImage(named: diagram.name, using: viewModel)
    }
}
