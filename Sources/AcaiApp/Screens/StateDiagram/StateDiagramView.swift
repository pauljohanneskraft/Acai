import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiRender
import UniformTypeIdentifiers

/// Movement-only view for a generated state diagram: regenerates from the stored variable
/// configuration and lets the user drag state nodes, built on the shared canvas layer
/// (`PannableCanvas`, undo/redo) like the sequence view. Analysis failures replace the canvas
/// with an explanation and a path back to the configuration popup.
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
    @State private var canvasViewportSize = CGSize(width: 900, height: 600)
    @State private var showSidebar = false
    @State private var sidebarTab: StateDiagramSidebarTab = .settings
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

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
        sidebarPresentedCanvas
            .toolbar { toolbarContent }
            .diagramCanvasLifecycle(
                title: diagram.name, model: viewModel, onSave: savePositions, onCenter: centerDiagram
            )
            .userActivity(DiagramHandoffActivity.activityType) {
                DiagramHandoffActivity(diagram: diagram, codebase: codebase).configure($0)
            }
    }

    /// See `ClassDiagramView.sidebarPresentedCanvas`'s doc comment for why compact width (iPhone)
    /// uses a real `.sheet` here instead of relying on `.inspector`'s own collapsed presentation.
    @ViewBuilder
    private var sidebarPresentedCanvas: some View {
        #if os(iOS)
        if isCompactWidth {
            diagramContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $showSidebar) {
                    NavigationStack {
                        sidebar
                            .navigationTitle(diagram.name)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(.app("View.StateDiagramView.Done")) { showSidebar = false }
                                        .accessibilityIdentifier("diagram.sidebarDoneButton")
                                }
                            }
                    }
                }
        } else {
            diagramContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspector(isPresented: $showSidebar) {
                    sidebar
                        .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
                }
        }
        #else
        diagramContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $showSidebar) {
                sidebar
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
            }
        #endif
    }

    private var sidebar: StateDiagramSidebar {
        StateDiagramSidebar(
            viewModel: viewModel, artifact: artifact, tab: $sidebarTab,
            onApply: { config in
                viewModel.applyConfiguration(config)
                model.diagrams.updateStateConfiguration(diagramID: diagram.id, configuration: config)
                centerDiagram()
            },
            onSaveAsFreeform: {
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
            },
            onExportImage: exportImage
        )
    }

    private var diagramContent: some View {
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
    }

    // MARK: - Canvas

    private var canvasContent: some View {
        PannableCanvas(
            model: viewModel,
            scale: $canvasScale,
            offset: $canvasOffset,
            activeDragCanvasLocation: activeDragCanvasLocation,
            autoPanController: canvasAutoPanController,
            onViewportSizeChange: { canvasViewportSize = $0 },
            content: {
                let layout = viewModel.layout
                ZStack(alignment: .topLeading) {
                    StateEnsembleView(layout: layout)
                    ForEach(layout.nodes) { node in
                        stateNode(node)
                    }
                    ForEach(layout.edges) { edge in
                        transitionTapTarget(edge, layout: layout)
                    }
                }
            }
        )
    }

    private func stateNode(_ node: StateLayoutModel.NodeFrame) -> some View {
        StateNodeView(
            state: node.state,
            isSelected: viewModel.selectedNodeIDs.contains(node.id)
        )
        .frame(width: node.rect.width, height: node.rect.height)
        .position(x: node.rect.midX, y: node.rect.midY)
        .onTapGesture(count: 2) {
            viewModel.selectNode(node.id, extending: false)
            sidebarTab = .inspector
            showSidebar = true
        }
        .diagramNodeInteraction(
            id: node.id,
            model: viewModel,
            dragStartPositions: $dragStartPositions,
            activeDragCanvasLocation: $activeDragCanvasLocation,
            onCommit: savePositions
        )
    }

    /// An invisible tap strip over a transition arrow, selecting it for the Inspector tab —
    /// same rationale as `SequenceDiagramView.messageTapTarget`, sized to a full 44pt hit area.
    private func transitionTapTarget(_ edge: StateLayoutModel.EdgeLayout, layout: StateLayoutModel) -> some View {
        let midpoint: CGPoint = {
            guard let from = layout.frame(for: edge.from), let to = layout.frame(for: edge.to) else {
                return .zero
            }
            return CGPoint(x: (from.midX + to.midX) / 2, y: (from.midY + to.midY) / 2)
        }()
        let isSelected = viewModel.selectedTransitionID == edge.id
        return RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            #if os(macOS)
            .cursorOnHover(.pointingHand)
            #endif
            .frame(width: 44, height: 44)
            .position(midpoint)
            .accessibilityElement()
            .accessibilityLabel(
                edge.label.map { Text(.app("View.StateDiagramView.TransitionLabel \($0)")) }
                    ?? Text(.app("View.StateDiagramView.Transition"))
            )
            .accessibilityAddTraits(.isButton)
            .onTapGesture(count: 2) {
                viewModel.clearSelection()
                viewModel.selectedTransitionID = edge.id
                sidebarTab = .inspector
                showSidebar = true
            }
            .onTapGesture(count: 1) {
                let newSelection: Int? = (viewModel.selectedTransitionID == edge.id) ? nil : edge.id
                viewModel.clearSelection()
                viewModel.selectedTransitionID = newSelection
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            UndoRedoToolbarButtons(model: viewModel, onChange: savePositions)
            #if !os(macOS)
            MultiSelectToggleButton(model: viewModel)
            #endif

            Button {
                centerDiagram()
            } label: {
                Label(.app("View.StateDiagramView.FitView"), systemImage: "rectangle.dashed")
            }
            .help(.app("View.StateDiagramView.FitDiagramVisibleCanvas"))
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityIdentifier("diagram.fitToViewButton")
            Button {
                showSidebar.toggle()
            } label: {
                Label(.app("View.StateDiagramView.Sidebar"), systemImage: "sidebar.trailing")
            }
            .help(.app("View.StateDiagramView.ToggleSidebar"))
            .accessibilityIdentifier("diagram.sidebarToggleButton")
        }
    }

    // MARK: - Failure / unconfigured states

    private func failureState(_ error: StateDiagramAnalysisError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.StateDiagramView.VariableSStatesCan"))
                .foregroundStyle(.secondary)
            Text(verbatim: error.message)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                sidebarTab = .settings
                showSidebar = true
            } label: {
                Label(.app("View.StateDiagramView.EditConfiguration"), systemImage: "slider.horizontal.3")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unconfiguredState: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.hexagonpath")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.StateDiagramView.StateDiagramHasNo"))
                .foregroundStyle(.secondary)
            Button {
                sidebarTab = .settings
                showSidebar = true
            } label: {
                Label(.app("View.StateDiagramView.Configure"), systemImage: "slider.horizontal.3")
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
            rect: { viewModel.nodeRect($0) },
            viewport: canvasViewportSize
        ).transform else { return }
        canvasScale = fit.scale
        canvasOffset = fit.offset
        savePositions()
    }

    private func exportImage() {
        model.exportImage(named: diagram.name, using: viewModel)
    }
}
