import SwiftUI
import AcaiCore
import AcaiRender
import UniformTypeIdentifiers

/// View for a stored (generated) diagram that persists positions and supports re-generation.
struct ClassDiagramView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: ClassDiagramViewModel

    @State var canvasScale: CGFloat
    @State var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var activeResizeState: DiagramResizeState?
    @State private var showSidebar = false
    @State private var sidebarTab: ClassDiagramSidebarTab = .settings
    @State private var hasCenteredAfterMeasurement = false

    init(
        diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase,
        comparisonArtifact: CodeArtifact? = nil
    ) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        let restoredSizes = diagram.nodeSizes.mapValues { $0.cgSize }
        self._viewModel = StateObject(wrappedValue: ClassDiagramViewModel(
            codebase: codebase,
            artifact: artifact,
            configuration: diagram.classConfiguration ?? .init(),
            restoredPositions: diagram.nodePositions.mapValues { $0.cgPoint },
            restoredSizes: restoredSizes,
            comparisonArtifact: comparisonArtifact
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        canvasContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $showSidebar) {
                ClassDiagramSidebar(
                    viewModel: viewModel,
                    diagram: diagram,
                    artifact: artifact,
                    tab: $sidebarTab
                )
                .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
            }
            .onPreferenceChange(NodeSizePreferenceKey.self) { sizes in
                viewModel.updateMeasuredSizes(sizes)
                // The initial auto-fit (`diagramCanvasLifecycle`'s fixed delay) can run before nodes
                // report their real measured sizes, landing the camera on a stale, empty-looking fit.
                // Re-fit once real sizes are in, so a freshly generated diagram opens on its content.
                if !hasCenteredAfterMeasurement && viewModel.hasPerformedMeasuredLayout {
                    hasCenteredAfterMeasurement = true
                    centerDiagram()
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    UndoRedoToolbarButtons(model: viewModel, onChange: savePositions)
                    #if !os(macOS)
                    MultiSelectToggleButton(model: viewModel)
                    #endif

                    Button {
                        viewModel.recordUndo()
                        viewModel.performLayout()
                        centerDiagram()
                    } label: {
                        Label("Re-layout", systemImage: "rectangle.3.group")
                    }
                    .help("Re-run automatic layout")
                    Button {
                        centerDiagram()
                    } label: {
                        Label("Fit to View", systemImage: "rectangle.dashed")
                    }
                    .help("Fit the diagram to the visible canvas (⌘0)")
                    .keyboardShortcut("0", modifiers: .command)
                    Button {
                        model.saveAsFreeformDiagram(
                            id: diagram.id,
                            positions: viewModel.nodePositions,
                            scale: canvasScale,
                            offset: canvasOffset
                        )
                    } label: {
                        Label("Save as Freeform", systemImage: "document.on.document")
                    }
                    .help("Save a copy as an editable Freeform diagram")
                    Button {
                        exportImage()
                    } label: {
                        Label("Export Image", systemImage: "photo")
                    }
                    .help("Export the diagram as an image")
                    Button {
                        showSidebar.toggle()
                    } label: {
                        Label("Sidebar", systemImage: "sidebar.trailing")
                    }
                    .help("Toggle the sidebar")
                }
            }
            .diagramCanvasLifecycle(
                title: diagram.name, model: viewModel, onSave: savePositions, onCenter: centerDiagram
            )
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        PannableCanvas(
            model: viewModel,
            scale: $canvasScale,
            offset: $canvasOffset,
            activeDragCanvasLocation: activeDragCanvasLocation,
            autoPanController: canvasAutoPanController
        ) {
            ZStack {
                GroupingBoxLayer(viewModel: viewModel)
                nodeLayer
                edgeLayer
                resizeHandleLayer
                selectionRectangleLayer
            }
        }
    }

    // MARK: - Edge Layer

    @ViewBuilder private var edgeLayer: some View {
        let edges = viewModel.edges.removingDuplicates(by: \.id)
        ForEach(edges) { edge in
            if let sourceRect = viewModel.nodeRect(for: edge.sourceID),
               let targetRect = viewModel.nodeRect(for: edge.targetID) {
                RelationshipEdgeView(
                    kind: edge.kind,
                    sourceRect: sourceRect,
                    targetRect: targetRect,
                    sourceLabel: edge.sourceLabel,
                    targetLabel: edge.targetLabel,
                    strokeColor: viewModel.deltaColor(for: edge)
                )
            }
        }
    }

    // MARK: - Node Layer

    private var editor: ClassDiagramConfigEditor {
        ClassDiagramConfigEditor(model: model, viewModel: viewModel, diagramID: diagram.id, artifact: artifact)
    }

    @ViewBuilder private var nodeLayer: some View {
        let nodes = viewModel.nodes.removingDuplicates { $0.id }
        ForEach(nodes) { node in
            if let position = viewModel.nodePositions[node.id] {
                let hasUserSize = viewModel.userNodeSizes[node.id] != nil
                let size = viewModel.effectiveSize(for: node.id)
                let selected = viewModel.selectedNodeIDs.contains(node.id)
                let deltaBorder = viewModel.deltaColor(for: node)
                Group {
                    if hasUserSize {
                        TypeNodeView(node: node, isSelected: selected, borderOverride: deltaBorder)
                            .frame(width: size.width, height: size.height)
                            .contentShape(Rectangle().inset(by: 6))
                    } else {
                        TypeNodeView(node: node, isSelected: selected, borderOverride: deltaBorder)
                            .measuredNode(id: node.id)
                    }
                }
                .position(position)
                .onTapGesture(count: 2) {
                    viewModel.selectNode(node.id, extending: false)
                    sidebarTab = .inspector
                    showSidebar = true
                }
                .onTapGesture(count: 1) {
                    #if os(macOS)
                    let extending = NSEvent.modifierFlags.contains(.command)
                    #else
                    let extending = viewModel.isMultiSelectActive
                    #endif
                    viewModel.selectNode(node.id, extending: extending)
                }
                .highPriorityGesture(viewModel.nodeDragGesture(
                    id: node.id,
                    dragStartPositions: $dragStartPositions,
                    activeDragCanvasLocation: $activeDragCanvasLocation,
                    onCommit: savePositions
                ))
                .contextMenu {
                    Button {
                        viewModel.selectNode(node.id, extending: false)
                        sidebarTab = .inspector
                        showSidebar = true
                    } label: {
                        Label("Details", systemImage: "info")
                    }
                    Divider()
                    Toggle("Show Members", isOn: editor.typeVisibility(
                        node.id, override: \.propertyVisibility, default: \.showProperties))
                    Toggle("Show Functions", isOn: editor.typeVisibility(
                        node.id, override: \.methodVisibility, default: \.showMethods))
                    if node.kind == .enum {
                        Toggle("Show Enum Cases", isOn: editor.typeVisibility(
                            node.id, override: \.enumCaseVisibility, default: \.showEnumCases))
                    }
                }
            }
        }
    }

    // MARK: - Resize Handle Layer

    @ViewBuilder private var resizeHandleLayer: some View {
        let nodes = viewModel.nodes
            .filter { viewModel.selectedNodeIDs.contains($0.id) }
            .removingDuplicates(by: \.id)
        ForEach(nodes) { node in
            if let position = viewModel.nodePositions[node.id] {
                let size = viewModel.effectiveSize(for: node.id)
                CanvasResizeHandle(
                    id: node.id,
                    model: viewModel,
                    position: position,
                    size: size,
                    activeResizeState: $activeResizeState,
                    onCommit: savePositions
                )
            }
        }
    }

    // MARK: - Selection Rectangle

    @ViewBuilder
    private var selectionRectangleLayer: some View {
        if let rect = viewModel.selectionRect {
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 1)
                .background(Color.accentColor.opacity(0.1))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

}

// MARK: - Image Export

extension ClassDiagramView {
    /// Prompts for a destination, then renders the current diagram (WYSIWYG, including user drags)
    /// to PNG and writes it. Rendering happens only after the user confirms, so cancelling the save
    /// panel wastes no work — important for large diagrams where rendering is slow.
    private func exportImage() {
        model.exportImage(named: diagram.name, using: viewModel)
    }
}

// MARK: - Save & Center

extension ClassDiagramView {
    private func savePositions() {
        model.diagrams.updatePositions(
            diagramID: diagram.id,
            positions: viewModel.nodePositions,
            sizes: viewModel.userNodeSizes,
            scale: canvasScale,
            offset: canvasOffset
        )
    }

    private func centerDiagram() {
        guard let fit = FitToView(
            nodeIDs: viewModel.nodes.map(\.id),
            rect: { viewModel.nodeRect(for: $0) }
        ).transform else { return }
        canvasScale = fit.scale
        canvasOffset = fit.offset
        savePositions()
    }
}
