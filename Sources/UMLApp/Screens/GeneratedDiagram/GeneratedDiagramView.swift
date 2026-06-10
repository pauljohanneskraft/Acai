import SwiftUI
import UMLCore
import UMLRender
import UniformTypeIdentifiers

/// View for a stored (generated) diagram that persists positions and supports re-generation.
struct GeneratedDiagramView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: GeneratedDiagramViewModel

    @State var canvasScale: CGFloat
    @State var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var activeResizeState: DiagramResizeState?
    @State private var showSidebar = false
    @State private var sidebarTab: GeneratedDiagramSidebarTab = .settings

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        let restoredSizes = diagram.nodeSizes.mapValues { $0.cgSize }
        self._viewModel = StateObject(wrappedValue: GeneratedDiagramViewModel(
            codebase: codebase,
            artifact: artifact,
            configuration: diagram.configuration,
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
                GeneratedDiagramSidebar(
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
                Button {
                    performUndo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .help("Undo (⌘Z)")

                Button {
                    performRedo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .help("Redo (⇧⌘Z)")

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
        .background { keyboardShortcuts }
        .navigationTitle(diagram.name)
        .task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1))
            centerDiagram()
        }
        .onDisappear { savePositions() }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        InfiniteCanvas(scale: $canvasScale, offset: $canvasOffset, onSelectionRect: { rect in
            viewModel.selectNodes(in: rect)
        }, onBackgroundTap: {
            viewModel.clearSelection()
        }, autoPanDragLocation: activeDragCanvasLocation, onAutoPanDelta: { canvasDelta in
            for nodeID in viewModel.selectedNodeIDs {
                if let pos = viewModel.nodePositions[nodeID] {
                    viewModel.moveNode(nodeID, to: CGPoint(
                        x: pos.x + canvasDelta.width,
                        y: pos.y + canvasDelta.height
                    ))
                }
            }
        }, autoPanController: canvasAutoPanController, content: {
            ZStack {
                GroupingBoxLayer(viewModel: viewModel)
                nodeLayer
                edgeLayer
                resizeHandleLayer
                selectionRectangleLayer
            }
        })
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
                            .fixedSize()
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: NodeSizePreferenceKey.self,
                                        value: [node.id: geo.size]
                                    )
                                }
                            )
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
                .highPriorityGesture(nodeDragGesture(for: node.id))
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
                storedEdgeResizeHandles(for: node.id, at: position, size: size)
            }
        }
    }

    private func storedEdgeResizeHandles(for id: String, at position: CGPoint, size: CGSize) -> some View {
        let handleSize: CGFloat = 16
        return Rectangle()
            .fill(Color.clear)
            #if os(macOS)
            .cursorOnHover(.closedHand)
            #endif
            .frame(width: handleSize, height: handleSize)
            .contentShape(Rectangle())
            .position(x: position.x + size.width / 2, y: position.y + size.height / 2)
            .gesture(storedResizeGesture(for: id))
    }

    private func storedResizeGesture(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeResizeState == nil {
                    viewModel.recordUndo()
                    activeResizeState = .init(
                        startSize: viewModel.effectiveSize(for: id),
                        startPosition: viewModel.nodePositions[id] ?? .zero
                    )
                }
                guard let state = activeResizeState else { return }
                let minW: CGFloat = 80, minH: CGFloat = 50
                let newW = max(minW, state.startSize.width + value.translation.width)
                let newH = max(minH, state.startSize.height + value.translation.height)
                let dw = newW - state.startSize.width
                let dh = newH - state.startSize.height
                viewModel.resizeNode(id, width: newW, height: newH)
                viewModel.moveNode(
                    id,
                    to: CGPoint(
                        x: state.startPosition.x + dw / 2,
                        y: state.startPosition.y + dh / 2
                    )
                )
            }
            .onEnded { _ in
                activeResizeState = nil
                savePositions()
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

    // MARK: - Node Dragging (Group-Aware)

    private func nodeDragGesture(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartPositions.isEmpty {
                    viewModel.recordUndo()
                    if !viewModel.selectedNodeIDs.contains(id) {
                        viewModel.selectedNodeIDs = [id]
                    }
                    for nodeID in viewModel.selectedNodeIDs {
                        dragStartPositions[nodeID] = viewModel.nodePositions[nodeID]
                    }
                }
                let tx = value.translation.width
                let ty = value.translation.height
                for nodeID in viewModel.selectedNodeIDs {
                    guard let start = dragStartPositions[nodeID] else { continue }
                    viewModel.moveNode(nodeID, to: CGPoint(
                        x: start.x + tx,
                        y: start.y + ty
                    ))
                }
                if let start = dragStartPositions[id] {
                    activeDragCanvasLocation = CGPoint(
                        x: start.x + tx,
                        y: start.y + ty
                    )
                }
            }
            .onEnded { _ in
                dragStartPositions = [:]
                activeDragCanvasLocation = nil
                savePositions()
            }
    }

}

// MARK: - Image Export

extension GeneratedDiagramView {
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

extension GeneratedDiagramView {
    /// Hidden buttons that capture the Undo / Redo keyboard shortcuts.
    @ViewBuilder private var keyboardShortcuts: some View {
        Group {
            Button("") {
                performUndo()
            }
            .keyboardShortcut("z", modifiers: .command)

            Button("") {
                performRedo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .hidden()
    }

    /// Undo and persist. Single entry point so the save can't be forgotten at a call site.
    private func performUndo() {
        viewModel.undo()
        savePositions()
    }

    /// Redo and persist. Single entry point so the save can't be forgotten at a call site.
    private func performRedo() {
        viewModel.redo()
        savePositions()
    }

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
        guard !viewModel.nodePositions.isEmpty else { return }
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude
        for (id, pos) in viewModel.nodePositions {
            let size = viewModel.effectiveSize(for: id)
            minX = min(minX, pos.x - size.width / 2)
            minY = min(minY, pos.y - size.height / 2)
            maxX = max(maxX, pos.x + size.width / 2)
            maxY = max(maxY, pos.y + size.height / 2)
        }
        let diagramWidth = maxX - minX
        let diagramHeight = maxY - minY
        let padding: CGFloat = 60
        let viewWidth: CGFloat = 900, viewHeight: CGFloat = 600
        let scaleX = (viewWidth - padding * 2) / max(diagramWidth, 1)
        let scaleY = (viewHeight - padding * 2) / max(diagramHeight, 1)
        let fitScale = min(min(scaleX, scaleY), 1.2)
        canvasScale = max(fitScale, 0.2)
        canvasOffset = CGPoint(
            x: (viewWidth - diagramWidth * canvasScale) / 2 - minX * canvasScale,
            y: (viewHeight - diagramHeight * canvasScale) / 2 - minY * canvasScale
        )
        savePositions()
    }
}
