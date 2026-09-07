import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiRender
import AcaiQuality
import UniformTypeIdentifiers

/// Movement-only view for a generated package (module-dependency) diagram. Derives the diagram
/// from the artifact and lets the user drag module nodes, on the shared canvas layer
/// (`PannableCanvas`, drag gesture, undo/redo) like the state view. Modules render as UML package
/// shapes (the same `ContainerNodeView` the freeform editor uses) tinted by their distance from
/// the main sequence; dependencies are dashed arrows whose thickness encodes their weight. All
/// numeric coupling metrics live in the inspector sidebar, never on the canvas.
struct PackageDiagramView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase
    let isComparePresented: Binding<Bool>

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: PackageDiagramViewModel

    @State private var canvasScale: CGFloat
    @State private var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var showSidebar = false
    @State private var sidebarTab: PackageDiagramSidebarTab = .settings
    @State private var canvasViewportSize = CGSize(width: 900, height: 600)
    @State private var showSaveAsFreeformOptions = false
    @State private var includeMetricsNoteOnSave = false
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
        self._viewModel = StateObject(wrappedValue: PackageDiagramViewModel(
            artifact: artifact,
            filter: diagram.packageDiagramFilter,
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
            canvasContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $showSidebar) {
                    NavigationStack {
                        sidebar
                            .navigationTitle(.app("View.PackageDiagramView.PackageDiagram"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(.app("View.PackageDiagramView.Done")) { showSidebar = false }
                                        .accessibilityIdentifier("diagram.sidebarDoneButton")
                                }
                            }
                    }
                }
        } else {
            canvasContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspector(isPresented: $showSidebar) {
                    sidebar
                        .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
                }
        }
        #else
        canvasContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $showSidebar) {
                sidebar
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
            }
        #endif
    }

    /// Save as Freeform/Export Image move into the Settings tab; the Inspector tab becomes
    /// selection-scoped (`PackageDiagramInspector`), with `onSelect` letting a related-module row
    /// jump the canvas selection there directly.
    private var sidebar: PackageDiagramSidebar {
        PackageDiagramSidebar(
            diagram: viewModel.diagram,
            selectedNodeIDs: viewModel.selectedNodeIDs,
            filter: filterBinding,
            codebaseID: codebase.id,
            artifact: artifact,
            tab: $sidebarTab,
            onSelect: { viewModel.selectNode($0, extending: false) },
            onSaveAsFreeform: confirmSaveAsFreeform,
            onExportImage: exportImage,
            showSaveAsFreeformOptions: $showSaveAsFreeformOptions,
            includeMetricsNoteOnSave: $includeMetricsNoteOnSave
        )
    }

    private var filterBinding: Binding<AcaiQuality.Selector?> {
        Binding(
            get: { viewModel.filter },
            set: { newValue in
                model.diagrams.updatePackageDiagramFilter(diagramID: diagram.id, filter: newValue)
                viewModel.applyFilter(newValue)
            }
        )
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
                    packageEdges(layout)
                    ForEach(layout.nodes) { node in
                        moduleNode(node)
                    }
                }
            }
        )
        // Overlay inside the canvas (not a sibling spanning the inspector column too), so it doesn't
        // render on top of the inspector when open — same as PannableCanvas's zoom indicator.
        .overlay(alignment: .topTrailing) {
            CompareOverlayButton(diagram: diagram, isPresented: isComparePresented)
        }
    }

    private func packageEdges(_ layout: PackageLayoutModel) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.edges) { edge in
                if let sourceRect = layout.frame(for: edge.from),
                   let targetRect = layout.frame(for: edge.to) {
                    RelationshipEdgeView(
                        kind: .dependency,
                        sourceRect: sourceRect,
                        targetRect: targetRect,
                        lineWidthScale: Self.lineWidthScale(forWeight: edge.weight),
                        strokeColor: viewModel.edgeDeltaColor(from: edge.from, to: edge.to)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func deltaBorder(_ color: Color?) -> some View {
        if let color {
            RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3)
        }
    }

    private func moduleNode(_ node: PackageLayoutModel.NodeFrame) -> some View {
        ContainerNodeView(
            name: node.node.name,
            stereotype: "package",
            style: .package,
            isSelected: viewModel.selectedNodeIDs.contains(node.id),
            size: node.rect.size,
            fillColor: Color(hex: node.node.zoneColorHex)
        )
        .frame(width: node.rect.width, height: node.rect.height)
        .overlay(deltaBorder(viewModel.nodeDeltaColor(id: node.id)))
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

    private static func lineWidthScale(forWeight weight: Int) -> CGFloat {
        min(1 + CGFloat(weight - 1) * 0.35, 3)
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
                Label(.app("View.PackageDiagramView.FitView"), systemImage: "rectangle.dashed")
            }
            .help(.app("View.PackageDiagramView.FitDiagramVisibleCanvas"))
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityIdentifier("diagram.fitToViewButton")
            Button {
                showSidebar.toggle()
            } label: {
                Label(.app("View.PackageDiagramView.Sidebar"), systemImage: "sidebar.trailing")
            }
            .help(.app("View.PackageDiagramView.ToggleSidebar"))
            .accessibilityIdentifier("diagram.sidebarToggleButton")
        }
    }

    private func exportImage() {
        model.exportImage(named: diagram.name, using: viewModel)
    }

    // MARK: - Save as Freeform (opt-in metric carryover)

    /// Confirms the "Save as Freeform" action with one opt-in: whether to carry over the module
    /// coupling figures already computed for this diagram as a read-only note. Reflects the
    /// current, non-diff artifact even when `Compare vs git` is active — the converted copy is
    /// always built from the plain current tree, same as the rest of this conversion.
    private func confirmSaveAsFreeform() {
        let layoutPositions = Dictionary(
            viewModel.layout.nodes.map { ($0.id, CGPoint(x: $0.rect.midX, y: $0.rect.midY)) },
            uniquingKeysWith: { first, _ in first }
        )
        model.saveAsFreeformDiagram(
            id: diagram.id,
            positions: layoutPositions,
            scale: canvasScale,
            offset: canvasOffset,
            includeMetricsNote: includeMetricsNoteOnSave
        )
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
}
