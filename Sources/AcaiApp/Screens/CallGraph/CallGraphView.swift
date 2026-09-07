import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiRender
import AcaiQuality
import UniformTypeIdentifiers

struct CallGraphView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase
    let isComparePresented: Binding<Bool>
    let comparisonArtifact: CodeArtifact?

    @EnvironmentObject private var model: ProjectBrowserViewModel

    init(
        diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase,
        isComparePresented: Binding<Bool>, comparisonArtifact: CodeArtifact? = nil
    ) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        self.isComparePresented = isComparePresented
        self.comparisonArtifact = comparisonArtifact
    }

    private var scope: CallGraphScope {
        if case .callGraph(let configured) = diagram.content { return configured }
        return .wholeCodebase
    }

    var body: some View {
        CallGraphCanvasView(
            diagram: diagram,
            artifact: artifact,
            codebase: codebase,
            scope: scope,
            filter: diagram.callGraphFilter,
            isComparePresented: isComparePresented,
            comparisonArtifact: comparisonArtifact,
            onApplyScope: { newScope in
                model.diagrams.updateCallGraphScope(diagramID: diagram.id, scope: newScope)
            }
        )
        .id(scope)
        .userActivity(DiagramHandoffActivity.activityType) {
            DiagramHandoffActivity(diagram: diagram, codebase: codebase).configure($0)
        }
    }
}

private struct CallGraphCanvasView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase
    let scope: CallGraphScope
    let isComparePresented: Binding<Bool>
    let onApplyScope: (CallGraphScope) -> Void

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: CallGraphViewModel

    @State private var canvasScale: CGFloat
    @State private var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var showSidebar = false
    @State private var sidebarTab: CallGraphSidebarTab = .settings
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
        diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase, scope: CallGraphScope,
        filter: AcaiQuality.Selector?,
        isComparePresented: Binding<Bool>, comparisonArtifact: CodeArtifact? = nil,
        onApplyScope: @escaping (CallGraphScope) -> Void
    ) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        self.scope = scope
        self.isComparePresented = isComparePresented
        self.onApplyScope = onApplyScope
        self._viewModel = StateObject(wrappedValue: CallGraphViewModel(
            artifact: artifact,
            scope: scope,
            filter: filter,
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

    @ViewBuilder
    private var sidebarPresentedCanvas: some View {
        #if os(iOS)
        if isCompactWidth {
            canvasContent
                .overlay(alignment: .top) { coverageBanner }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $showSidebar) {
                    NavigationStack {
                        sidebar
                            .navigationTitle(.app("View.CallGraphCanvasView.CallGraph"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(.app("View.CallGraphCanvasView.Done")) { showSidebar = false }
                                        .accessibilityIdentifier("diagram.sidebarDoneButton")
                                }
                            }
                    }
                }
        } else {
            canvasContent
                .overlay(alignment: .top) { coverageBanner }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspector(isPresented: $showSidebar) {
                    sidebar
                        .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
                }
        }
        #else
        canvasContent
            .overlay(alignment: .top) { coverageBanner }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $showSidebar) {
                sidebar
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
            }
        #endif
    }

    private var sidebar: CallGraphSidebar {
        CallGraphSidebar(
            artifact: artifact,
            graph: viewModel.graph,
            selectedNodeIDs: viewModel.selectedNodeIDs,
            scope: scope,
            filter: filterBinding,
            codebaseID: codebase.id,
            tab: $sidebarTab,
            onSelect: { viewModel.selectNode($0, extending: false) },
            onApplyScope: onApplyScope,
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
                model.diagrams.updateCallGraphFilter(diagramID: diagram.id, filter: newValue)
                viewModel.applyFilter(newValue)
            }
        )
    }

    // MARK: - Coverage banner

    private var coverageBanner: some View {
        let coverage = viewModel.graph.coverage
        let percent = Int((coverage.fraction * 100).rounded())
        return HStack(spacing: 6) {
            Image(systemName: percent == 100 ? "checkmark.seal" : "exclamationmark.triangle")
            Text(.app("View.CallGraphCanvasView.ResolvedCallSites \(coverage.resolved) \(coverage.total) \(percent)"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .padding(.top, 8)
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
                    callEdges(layout)
                    ForEach(layout.nodes) { node in
                        methodNode(node)
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

    private func callEdges(_ layout: CallGraphLayoutModel) -> some View {
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

    private func methodNode(_ node: CallGraphLayoutModel.NodeFrame) -> some View {
        CallGraphNodeView(
            node: node.node,
            isSelected: viewModel.selectedNodeIDs.contains(node.id)
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
                Label(.app("View.CallGraphCanvasView.FitView"), systemImage: "rectangle.dashed")
            }
            .help(.app("View.CallGraphCanvasView.FitDiagramVisibleCanvas"))
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityIdentifier("diagram.fitToViewButton")
            Button {
                showSidebar.toggle()
            } label: {
                Label(.app("View.CallGraphCanvasView.Sidebar"), systemImage: "sidebar.trailing")
            }
            .help(.app("View.CallGraphCanvasView.ToggleSidebar"))
            .accessibilityIdentifier("diagram.sidebarToggleButton")
        }
    }

    private func exportImage() {
        model.exportImage(named: diagram.name, using: viewModel)
    }

    // MARK: - Save as Freeform (opt-in metric carryover)

    /// Reflects the current, non-diff artifact even when `Compare vs git` is active — the converted
    /// copy is always built from the plain current tree.
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

private struct CallGraphNodeView: View {
    let node: CallGraph.Node
    let isSelected: Bool

    private var fill: Color {
        node.inScope ? Color(red: 0.89, green: 0.95, blue: 0.99) : Color(white: 0.96)
    }

    var body: some View {
        Text(verbatim: node.label)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(white: 0.1))
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(white: 0.6),
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: node.inScope ? [] : [4, 3])
                    )
            )
            .accessibilityIdentifier("diagram.callGraphNode.\(node.id)")
    }
}
