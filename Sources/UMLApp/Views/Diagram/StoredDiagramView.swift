import SwiftUI
import UMLCore

// MARK: - Resize Support

private enum StoredResizeEdge {
    case left, right, top, bottom
}

private struct StoredResizeState {
    let startSize: CGSize
    let startPosition: CGPoint
}

/// View for a stored (generated) diagram that persists positions and supports re-generation.
struct StoredDiagramView: View {
    let diagram: StoredDiagram
    let artifact: CodeArtifact
    let codebaseName: String

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: ClassDiagramViewModel

    @State private var canvasScale: CGFloat
    @State private var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint? = nil
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var activeResizeState: StoredResizeState? = nil
    @State private var showingConfigSheet = false

    init(diagram: StoredDiagram, artifact: CodeArtifact, codebaseName: String) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebaseName = codebaseName
        let restoredSizes = diagram.nodeSizes.mapValues { $0.cgSize }
        self._viewModel = StateObject(wrappedValue: ClassDiagramViewModel(
            artifact: artifact,
            configuration: diagram.configuration,
            restoredPositions: diagram.nodePositions.mapValues { $0.cgPoint },
            restoredSizes: restoredSizes
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        InfiniteCanvas(scale: $canvasScale, offset: $canvasOffset, onSelectionRect: { rect in
            viewModel.selectNodes(in: rect)
        }, onBackgroundTap: {
            viewModel.clearSelection()
        }, autoPanDragLocation: activeDragCanvasLocation, onAutoPanDelta: { canvasDelta in
            // Move all dragged nodes by the incremental delta so they keep
            // up with the auto-pan while the cursor is stationary.
            for nodeID in viewModel.selectedNodeIDs {
                if let pos = viewModel.nodePositions[nodeID] {
                    viewModel.moveNode(nodeID, to: CGPoint(
                        x: pos.x + canvasDelta.width,
                        y: pos.y + canvasDelta.height
                    ))
                }
            }
        }, autoPanController: canvasAutoPanController) {
            ZStack {
                edgeLayer
                nodeLayer
                resizeHandleLayer
                selectionRectangleLayer
            }
        }
        .onPreferenceChange(NodeSizePreferenceKey.self) { sizes in
            viewModel.updateMeasuredSizes(sizes)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.performLayout()
                    centerDiagram()
                } label: {
                    Label("Re-layout", systemImage: "rectangle.3.group")
                }

                Button {
                    centerDiagram()
                } label: {
                    Label("Fit to View", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Button {
                    savePositions()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }

                Button {
                    showingConfigSheet = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }

                Button {
                    model.saveAsCustomDiagram(
                        storedDiagramID: diagram.id,
                        livePositions: viewModel.nodePositions,
                        liveScale: canvasScale,
                        liveOffset: canvasOffset
                    )
                } label: {
                    Label("Save as Custom", systemImage: "doc.badge.plus")
                }

                Text(codebaseName)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .navigationTitle(diagram.name)
        .onAppear {
            if diagram.canvasScale <= 0.01 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { centerDiagram() }
            }
        }
        .onDisappear {
            savePositions()
        }
        .sheet(isPresented: $showingConfigSheet) {
            DiagramConfigurationEditor(configuration: diagram.configuration) { newConfig in
                model.updateStoredDiagramConfiguration(diagramID: diagram.id, configuration: newConfig)
                viewModel.applyConfiguration(newConfig, artifact: artifact)
            }
        }
    }

    // MARK: - Edge Layer

    private var edgeLayer: some View {
        ForEach(viewModel.edges) { edge in
            if let sourceRect = viewModel.nodeRect(for: edge.sourceID),
               let targetRect = viewModel.nodeRect(for: edge.targetID) {
                RelationshipEdgeView(edge: edge, sourceRect: sourceRect, targetRect: targetRect)
            }
        }
    }

    // MARK: - Node Layer

    private var nodeLayer: some View {
        ForEach({
            var ids = Set<String>()
            return viewModel.nodes.filter { ids.insert($0.id).inserted }
        }()) { node in
            if let position = viewModel.nodePositions[node.id] {
                let hasUserSize = viewModel.userNodeSizes[node.id] != nil
                let size = viewModel.effectiveSize(for: node.id)
                let selected = viewModel.selectedNodeIDs.contains(node.id)

                Group {
                    if hasUserSize {
                        UMLTypeBoxView(
                            node: node,
                            isSelected: selected
                        )
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle().inset(by: 6))
                    } else {
                        UMLTypeBoxView(
                            node: node,
                            isSelected: selected
                        )
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
                .onTapGesture {
                    #if os(macOS)
                    let extending = NSEvent.modifierFlags.contains(.shift)
                    #else
                    let extending = false
                    #endif
                    viewModel.selectNode(node.id, extending: extending)
                }
                .highPriorityGesture(nodeDragGesture(for: node.id))
            }
        }
    }

    // MARK: - Resize Handle Layer

    private var resizeHandleLayer: some View {
        ForEach(viewModel.nodes.filter { viewModel.selectedNodeIDs.contains($0.id) }) { node in
            if let position = viewModel.nodePositions[node.id] {
                let size = viewModel.effectiveSize(for: node.id)
                storedEdgeResizeHandles(for: node.id, at: position, size: size)
            }
        }
    }

    private func storedEdgeResizeHandles(for id: String, at position: CGPoint, size: CGSize) -> some View {
        let thickness: CGFloat = 8
        return ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: thickness, height: size.height)
                .contentShape(Rectangle())
                .position(x: position.x + size.width / 2, y: position.y)
                .gesture(storedResizeGesture(for: id, edge: .right))
                #if os(macOS)
                .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                #endif

            Rectangle()
                .fill(Color.clear)
                .frame(width: thickness, height: size.height)
                .contentShape(Rectangle())
                .position(x: position.x - size.width / 2, y: position.y)
                .gesture(storedResizeGesture(for: id, edge: .left))
                #if os(macOS)
                .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                #endif

            Rectangle()
                .fill(Color.clear)
                .frame(width: size.width, height: thickness)
                .contentShape(Rectangle())
                .position(x: position.x, y: position.y + size.height / 2)
                .gesture(storedResizeGesture(for: id, edge: .bottom))
                #if os(macOS)
                .onHover { h in if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                #endif

            Rectangle()
                .fill(Color.clear)
                .frame(width: size.width, height: thickness)
                .contentShape(Rectangle())
                .position(x: position.x, y: position.y - size.height / 2)
                .gesture(storedResizeGesture(for: id, edge: .top))
                #if os(macOS)
                .onHover { h in if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                #endif
        }
    }

    private func storedResizeGesture(for id: String, edge: StoredResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeResizeState == nil {
                    activeResizeState = StoredResizeState(
                        startSize: viewModel.effectiveSize(for: id),
                        startPosition: viewModel.nodePositions[id] ?? .zero
                    )
                }
                guard let state = activeResizeState else { return }
                let minW: CGFloat = 80, minH: CGFloat = 50

                switch edge {
                case .right:
                    let newW = max(minW, state.startSize.width + value.translation.width)
                    let dw = newW - state.startSize.width
                    viewModel.resizeNode(id, width: newW, height: state.startSize.height)
                    viewModel.moveNode(id, to: CGPoint(x: state.startPosition.x + dw / 2, y: state.startPosition.y))
                case .left:
                    let newW = max(minW, state.startSize.width - value.translation.width)
                    let dw = newW - state.startSize.width
                    viewModel.resizeNode(id, width: newW, height: state.startSize.height)
                    viewModel.moveNode(id, to: CGPoint(x: state.startPosition.x - dw / 2, y: state.startPosition.y))
                case .bottom:
                    let newH = max(minH, state.startSize.height + value.translation.height)
                    let dh = newH - state.startSize.height
                    viewModel.resizeNode(id, width: state.startSize.width, height: newH)
                    viewModel.moveNode(id, to: CGPoint(x: state.startPosition.x, y: state.startPosition.y + dh / 2))
                case .top:
                    let newH = max(minH, state.startSize.height - value.translation.height)
                    let dh = newH - state.startSize.height
                    viewModel.resizeNode(id, width: state.startSize.width, height: newH)
                    viewModel.moveNode(id, to: CGPoint(x: state.startPosition.x, y: state.startPosition.y - dh / 2))
                }
            }
            .onEnded { _ in
                activeResizeState = nil
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
            }
    }

    // MARK: - Save & Center

    private func savePositions() {
        model.updateStoredDiagramPositions(
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
        let viewWidth: CGFloat = 900
        let viewHeight: CGFloat = 600

        let scaleX = (viewWidth - padding * 2) / max(diagramWidth, 1)
        let scaleY = (viewHeight - padding * 2) / max(diagramHeight, 1)
        let fitScale = min(min(scaleX, scaleY), 1.2)

        canvasScale = max(fitScale, 0.15)
        canvasOffset = CGPoint(
            x: (viewWidth - diagramWidth * canvasScale) / 2 - minX * canvasScale,
            y: (viewHeight - diagramHeight * canvasScale) / 2 - minY * canvasScale
        )
    }
}

// MARK: - Diagram Configuration Editor

struct DiagramConfigurationEditor: View {
    @State var configuration: DiagramConfiguration
    var onSave: (DiagramConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diagram Settings").font(.title2).bold()

            Form {
                Section("Visibility") {
                    Toggle("Show Properties", isOn: $configuration.showProperties)
                    Toggle("Show Methods", isOn: $configuration.showMethods)
                    Toggle("Show Enum Cases", isOn: $configuration.showEnumCases)
                }

                Section("Relationships") {
                    Toggle("Show Relationships", isOn: $configuration.showRelationships)
                    if configuration.showRelationships {
                        Toggle("Inheritance", isOn: $configuration.showInheritance)
                        Toggle("Composition", isOn: $configuration.showComposition)
                        Toggle("Dependency", isOn: $configuration.showDependency)
                    }
                }

                Section("Layout") {
                    Toggle("Group by Directory", isOn: $configuration.groupByDirectory)
                    Toggle("Show External Types", isOn: $configuration.showExternalTypes)
                }

                Section("Dart") {
                    Toggle("Hide Generated Types", isOn: $configuration.hideGeneratedDartTypes)
                    Text("Hides types from .freezed.dart, .g.dart and other code-generated files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    onSave(configuration)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 520)
    }
}
