import SwiftUI
import UMLCore
import UMLRender
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

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        let restoredSizes = diagram.nodeSizes.mapValues { $0.cgSize }
        self._viewModel = StateObject(wrappedValue: ClassDiagramViewModel(
            codebase: codebase,
            artifact: artifact,
            configuration: diagram.classConfiguration ?? .init(),
            restoredPositions: diagram.nodePositions.mapValues { $0.cgPoint },
            restoredSizes: restoredSizes
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        HSplitView {
            canvasContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showSidebar {
                ClassDiagramSidebar(
                    viewModel: viewModel,
                    diagram: diagram,
                    artifact: artifact,
                    tab: $sidebarTab
                ).frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
            }
        }
        .onPreferenceChange(NodeSizePreferenceKey.self) { sizes in
            viewModel.updateMeasuredSizes(sizes)
        }
        .toolbar {
            ToolbarItemGroup {
                UndoRedoToolbarButtons(model: viewModel, onChange: savePositions)

                Button {
                    viewModel.recordUndo()
                    viewModel.performLayout()
                    centerDiagram()
                } label: {
                    Label("Re-layout", systemImage: "rectangle.3.group")
                }
                Button {
                    centerDiagram()
                } label: {
                    Label("Fit to View", systemImage: "rectangle.dashed")
                }
                Button {
                    model.saveAsCustomDiagram(
                        id: diagram.id,
                        positions: viewModel.nodePositions,
                        scale: canvasScale,
                        offset: canvasOffset
                    )
                } label: {
                    Label("Save as Custom", systemImage: "document.on.document")
                }
                Button {
                    exportImage()
                } label: {
                    Label("Export Image", systemImage: "photo")
                }
                Button {
                    showSidebar.toggle()
                } label: {
                    Label("Sidebar", systemImage: "sidebar.trailing")
                }
            }
        }
        .undoRedoKeyboardShortcuts(model: viewModel, onChange: savePositions)
        .navigationTitle(diagram.name)
        .task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1))
            centerDiagram()
        }
        .onDisappear { savePositions() }
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
                    targetRect: targetRect
                )
            }
        }
    }

    // MARK: - Node Layer

    @ViewBuilder private var nodeLayer: some View {
        let nodes = viewModel.nodes.removingDuplicates { $0.id }
        ForEach(nodes) { node in
            if let position = viewModel.nodePositions[node.id] {
                let hasUserSize = viewModel.userNodeSizes[node.id] != nil
                let size = viewModel.effectiveSize(for: node.id)
                let selected = viewModel.selectedNodeIDs.contains(node.id)
                Group {
                    if hasUserSize {
                        TypeNodeView(node: node, isSelected: selected)
                            .frame(width: size.width, height: size.height)
                            .contentShape(Rectangle().inset(by: 6))
                    } else {
                        TypeNodeView(node: node, isSelected: selected)
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
                    let extending = false
                    #endif
                    viewModel.selectNode(node.id, extending: extending)
                }
                .highPriorityGesture(canvasNodeDragGesture(
                    id: node.id,
                    model: viewModel,
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
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(diagram.name).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try viewModel.exportPNGData()
            try data.write(to: url, options: .atomic)
        } catch {
            print("Image export failed: \(error)")
        }
        #endif
    }
}

// MARK: - Save & Center

extension ClassDiagramView {
    private func savePositions() {
        model.updateGeneratedDiagramPositions(
            diagramID: diagram.id,
            positions: viewModel.nodePositions,
            sizes: viewModel.userNodeSizes,
            scale: canvasScale,
            offset: canvasOffset
        )
    }

    private func centerDiagram() {
        guard let fit = fitToView(
            nodeIDs: viewModel.nodes.map(\.id),
            rect: { viewModel.nodeRect(for: $0) }
        ) else { return }
        canvasScale = fit.scale
        canvasOffset = fit.offset
        savePositions()
    }
}
