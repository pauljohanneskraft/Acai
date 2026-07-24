import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiRender
import UniformTypeIdentifiers

/// Generated static call-graph screen. A thin wrapper that owns the scope re-configuration sheet
/// and rebuilds the canvas (keyed by scope) when the scope changes, so re-scoping immediately
/// re-derives the graph. The heavy lifting lives in `CallGraphCanvasView`.
struct CallGraphView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase
    let comparisonArtifact: CodeArtifact?

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var isConfiguring = false

    init(
        diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase,
        comparisonArtifact: CodeArtifact? = nil
    ) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
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
            scope: scope,
            comparisonArtifact: comparisonArtifact,
            onConfigure: { isConfiguring = true }
        )
        .id(scope)
        .sheet(isPresented: $isConfiguring) {
            CallGraphConfigSheet(
                artifact: artifact,
                initial: scope,
                onCancel: { isConfiguring = false },
                onCreate: { newScope in
                    model.diagrams.updateCallGraphScope(diagramID: diagram.id, scope: newScope)
                    isConfiguring = false
                }
            )
        }
    }
}

/// Movement-only canvas for a static call graph at a fixed scope. Lets the user drag method nodes
/// on the shared canvas layer (`PannableCanvas`, drag gesture, undo/redo) like the package view.
/// Methods render as rounded boxes (in-scope solid, out-of-scope callees dashed); calls are arrows
/// whose thickness encodes their multiplicity. A banner reports static-resolution coverage.
private struct CallGraphCanvasView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let scope: CallGraphScope
    let onConfigure: () -> Void

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: CallGraphViewModel

    @State private var canvasScale: CGFloat
    @State private var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var showSidebar = true
    @State private var canvasViewportSize = CGSize(width: 900, height: 600)
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
        diagram: GeneratedDiagram, artifact: CodeArtifact, scope: CallGraphScope,
        comparisonArtifact: CodeArtifact? = nil, onConfigure: @escaping () -> Void
    ) {
        self.diagram = diagram
        self.artifact = artifact
        self.scope = scope
        self.onConfigure = onConfigure
        self._viewModel = StateObject(wrappedValue: CallGraphViewModel(
            artifact: artifact,
            scope: scope,
            restoredPositions: diagram.nodePositions.mapValues(\.cgPoint),
            comparisonArtifact: comparisonArtifact
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        canvasContent
            .overlay(alignment: .top) { coverageBanner }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $showSidebar) {
                CallGraphInspector(
                    graph: viewModel.graph,
                    selectedNodeIDs: viewModel.selectedNodeIDs,
                    isPresented: $showSidebar,
                    isCompactWidth: isCompactWidth
                )
                .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
            }
            .toolbar { toolbarContent }
            .diagramCanvasLifecycle(
                title: diagram.name, model: viewModel, onSave: savePositions, onCenter: centerDiagram
            )
    }

    // MARK: - Coverage banner

    private var coverageBanner: some View {
        let coverage = viewModel.graph.coverage
        let percent = Int((coverage.fraction * 100).rounded())
        return HStack(spacing: 6) {
            Image(systemName: percent == 100 ? "checkmark.seal" : "exclamationmark.triangle")
            Text("Resolved \(coverage.resolved)/\(coverage.total) call sites (\(percent)%)")
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

    /// A coloured delta outline overlaid on a node, or nothing when the node is unchanged.
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
        .diagramNodeInteraction(
            id: node.id,
            model: viewModel,
            dragStartPositions: $dragStartPositions,
            activeDragCanvasLocation: $activeDragCanvasLocation,
            onCommit: savePositions
        )
    }

    /// Maps a call's multiplicity to a line-width multiplier, clamped so the heaviest edges stay legible.
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
                Label("Fit to View", systemImage: "rectangle.dashed")
            }
            .help("Fit the diagram to the visible canvas (⌘0)")
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityIdentifier("diagram.fitToViewButton")
            Button(action: onConfigure) {
                Label("Configure Scope", systemImage: "slider.horizontal.3")
            }
            .help("Change the call graph's entry point and depth")
            .accessibilityIdentifier("diagram.configureButton")
            Button {
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
            .accessibilityIdentifier("diagram.saveAsFreeformButton")
            Button {
                exportImage()
            } label: {
                Label("Export Image", systemImage: "photo")
            }
            .help("Export the diagram as an image")
            .accessibilityIdentifier("diagram.exportImageButton")
            Button {
                showSidebar.toggle()
            } label: {
                Label("Sidebar", systemImage: "sidebar.trailing")
            }
            .help("Toggle the sidebar")
            .accessibilityIdentifier("diagram.sidebarToggleButton")
        }
    }

    private func exportImage() {
        model.exportImage(named: diagram.name, using: viewModel)
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

/// A single method box in the call graph: `Type.method`, solid for in-scope methods and dashed +
/// lighter for out-of-scope callee leaves so the focus stands out.
private struct CallGraphNodeView: View {
    let node: CallGraph.Node
    let isSelected: Bool

    private var fill: Color {
        node.inScope ? Color(red: 0.89, green: 0.95, blue: 0.99) : Color(white: 0.96)
    }

    var body: some View {
        Text(node.label)
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
            // Keyed by id (`Type.method`), same rationale/edge case as `TypeNodeView.accessibilityIdentifier`.
            .accessibilityIdentifier("diagram.callGraphNode.\(node.id)")
    }
}
