import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiDiff
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
    let isComparePresented: Binding<Bool>
    let comparisonArtifact: CodeArtifact?

    @EnvironmentObject private var model: ProjectBrowserViewModel
    // Not `private`: `StateDiagramView+Canvas.swift`'s extension (kept in its own file only to
    // stay under this file's own type-body-length limit) needs to read/write these too.
    @StateObject var viewModel: StateDiagramViewModel

    @State var canvasScale: CGFloat
    @State var canvasOffset: CGPoint
    @State var dragStartPositions: [String: CGPoint] = [:]
    @State var activeDragCanvasLocation: CGPoint?
    @State var canvasAutoPanController = EdgeAutoPanController()
    @State var canvasViewportSize = CGSize(width: 900, height: 600)
    @State var showSidebar = false
    @State var sidebarTab: StateDiagramSidebarTab = .settings
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

    init(
        diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase,
        isComparePresented: Binding<Bool>, comparisonArtifact: CodeArtifact? = nil
    ) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        self.isComparePresented = isComparePresented
        self.comparisonArtifact = comparisonArtifact
        self._viewModel = StateObject(wrappedValue: StateDiagramViewModel(
            artifact: artifact,
            configuration: diagram.stateConfiguration,
            restoredPositions: diagram.nodePositions.mapValues(\.cgPoint),
            comparisonArtifact: comparisonArtifact
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
            viewModel: viewModel, artifact: artifact, codebaseID: codebase.id, tab: $sidebarTab,
            onApply: { config in
                viewModel.applyConfiguration(config)
                model.diagrams.updateStateConfiguration(diagramID: diagram.id, configuration: config)
                centerDiagram()
            },
            onApplyFilter: { filter in
                viewModel.applyFilter(filter)
                model.diagrams.updateStateFilter(diagramID: diagram.id, filter: filter)
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
            .keyboardShortcut(.fitToView)
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
        VStack(spacing: Spacing.l) {
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
        VStack(spacing: Spacing.l) {
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

    func savePositions() {
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
