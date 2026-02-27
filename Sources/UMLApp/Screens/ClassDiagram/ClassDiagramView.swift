import SwiftUI
import UMLCore

/// Top-level view for the class diagram visualization.
/// Composes the infinite canvas with UML class boxes and relationship edges.
struct ClassDiagramView: View {
    @StateObject private var viewModel: ClassDiagramViewModel
    let codebaseName: String

    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGPoint = .zero
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()

    init(artifact: CodeArtifact, codebaseName: String) {
        self._viewModel = StateObject(wrappedValue: ClassDiagramViewModel(artifact: artifact))
        self.codebaseName = codebaseName
    }

    var body: some View {
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
                edgeLayer
                nodeLayer
                selectionRectangleLayer
            }
        })
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

                Text(codebaseName)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .navigationTitle("Class Diagram")
        .onAppear {
            // Delay to allow initial layout to complete.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                centerDiagram()
            }
        }
    }

    // MARK: - Edge Layer

    private var edgeLayer: some View {
        ForEach(viewModel.edges) { edge in
            if let sourceRect = viewModel.nodeRect(for: edge.sourceID),
               let targetRect = viewModel.nodeRect(for: edge.targetID) {
                RelationshipEdgeView(
                    edge: edge,
                    sourceRect: sourceRect,
                    targetRect: targetRect
                )
            }
        }
    }

    // MARK: - Node Layer

    private var nodeLayer: some View {

        ForEach(viewModel.nodes.removingDuplicates { $0.id }) { node in
            if let position = viewModel.nodePositions[node.id] {
                UMLTypeBoxView(
                    node: node,
                    isSelected: viewModel.selectedNodeIDs.contains(node.id)
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
                .position(position)
                .onTapGesture {
                    #if os(macOS)
                    let extending = NSEvent.modifierFlags.contains(.command)
                    #else
                    let extending = false
                    #endif
                    viewModel.selectNode(node.id, extending: extending)
                }
                .highPriorityGesture(nodeDragGesture(for: node.id))
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

    // MARK: - Center Diagram

    private func centerDiagram() {
        guard !viewModel.nodePositions.isEmpty else { return }

        // Compute bounding box of all nodes.
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude

        for (id, pos) in viewModel.nodePositions {
            let size = viewModel.nodeSizes[id] ?? CGSize(width: 200, height: 100)
            minX = min(minX, pos.x - size.width / 2)
            minY = min(minY, pos.y - size.height / 2)
            maxX = max(maxX, pos.x + size.width / 2)
            maxY = max(maxY, pos.y + size.height / 2)
        }

        let diagramWidth = maxX - minX
        let diagramHeight = maxY - minY
        let padding: CGFloat = 60

        // Default to a reasonable viewport size if we don't have geometry.
        let viewWidth: CGFloat = 900
        let viewHeight: CGFloat = 600

        let scaleX = (viewWidth - padding * 2) / max(diagramWidth, 1)
        let scaleY = (viewHeight - padding * 2) / max(diagramHeight, 1)
        let fitScale = min(min(scaleX, scaleY), 1.2) // Don't zoom in more than 1.2x

        canvasScale = max(fitScale, 0.15)
        canvasOffset = CGPoint(
            x: (viewWidth - diagramWidth * canvasScale) / 2 - minX * canvasScale,
            y: (viewHeight - diagramHeight * canvasScale) / 2 - minY * canvasScale
        )
    }
}
