import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender
import UniformTypeIdentifiers

/// Movement-only view for a generated state diagram. Regenerates the diagram from its stored
/// variable configuration and lets the user drag state nodes; built on the shared canvas layer
/// (`PannableCanvas`, drag gesture, undo/redo) like the sequence view. Analysis failures
/// (unbounded variables, too many states) replace the canvas with an explanation and a path
/// back to the configuration popup.
struct StateDiagramView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: StateDiagramViewModel

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
        self._viewModel = StateObject(wrappedValue: StateDiagramViewModel(
            artifact: artifact,
            configuration: diagram.stateConfiguration,
            restoredPositions: diagram.nodePositions.mapValues(\.cgPoint)
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        Group {
            switch viewModel.result {
            case .success:
                canvasContent
            case .failure(let error):
                failureState(error)
            case nil:
                unconfiguredState
            }
        }
        .toolbar { toolbarContent }
        .diagramCanvasLifecycle(
            title: diagram.name, model: viewModel, onSave: savePositions, onCenter: centerDiagram
        )
        .sheet(isPresented: $showConfigSheet) {
            StateConfigSheet(
                artifact: artifact,
                initial: viewModel.configuration,
                onCancel: { showConfigSheet = false },
                onCreate: { config in
                    viewModel.applyConfiguration(config)
                    model.diagrams.updateStateConfiguration(diagramID: diagram.id, configuration: config)
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
                StateEnsembleView(layout: layout)
                ForEach(layout.nodes) { node in
                    stateNode(node)
                }
            }
        }
    }

    private func stateNode(_ node: StateLayoutModel.NodeFrame) -> some View {
        StateNodeView(
            state: node.state,
            isSelected: viewModel.selectedNodeIDs.contains(node.id)
        )
        .frame(width: node.rect.width, height: node.rect.height)
        .position(x: node.rect.midX, y: node.rect.midY)
        .diagramNodeInteraction(
            id: node.id,
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
            .help("Change the state diagram's tracked variable")
            Button {
                // Pass every state's live centre (not just dragged overrides) so the freeform
                // copy reproduces the current layout exactly.
                let layoutPositions = Dictionary(
                    viewModel.layout.nodes.map { ($0.id, CGPoint(x: $0.rect.midX, y: $0.rect.midY)) },
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
            .disabled(viewModel.diagram == nil)
            Button {
                exportImage()
            } label: {
                Label("Export Image", systemImage: "photo")
            }
            .help("Export the diagram as an image")
            .disabled(viewModel.diagram == nil)
        }
    }

    // MARK: - Failure / unconfigured states

    private func failureState(_ error: StateDiagramAnalysisError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("This variable's states can't be enumerated.")
                .foregroundStyle(.secondary)
            Text(error.message)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                showConfigSheet = true
            } label: {
                Label("Edit Configuration", systemImage: "slider.horizontal.3")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unconfiguredState: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.hexagonpath")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("This state diagram has no variable selected yet.")
                .foregroundStyle(.secondary)
            Button {
                showConfigSheet = true
            } label: {
                Label("Configure", systemImage: "slider.horizontal.3")
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
            nodeIDs: viewModel.layout.nodes.map(\.id),
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
