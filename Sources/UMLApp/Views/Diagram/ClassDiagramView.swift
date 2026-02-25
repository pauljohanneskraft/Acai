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

    init(artifact: CodeArtifact, codebaseName: String) {
        self._viewModel = StateObject(wrappedValue: ClassDiagramViewModel(artifact: artifact))
        self.codebaseName = codebaseName
    }

    var body: some View {
        InfiniteCanvas(scale: $canvasScale, offset: $canvasOffset) {
            ZStack {
                edgeLayer
                nodeLayer
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
        ForEach(viewModel.nodes) { node in
            if let position = viewModel.nodePositions[node.id] {
                UMLClassBoxView(
                    node: node,
                    isSelected: viewModel.selectedNodeID == node.id
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
                    viewModel.selectedNodeID = (viewModel.selectedNodeID == node.id) ? nil : node.id
                }
                .highPriorityGesture(nodeDragGesture(for: node.id))
            }
        }
    }

    // MARK: - Node Dragging

    private func nodeDragGesture(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartPositions[id] == nil {
                    dragStartPositions[id] = viewModel.nodePositions[id]
                }
                guard let start = dragStartPositions[id] else { return }
                // DragGesture inside .scaleEffect already reports translation in
                // canvas coordinates, so no scale adjustment is needed.
                viewModel.moveNode(id, to: CGPoint(
                    x: start.x + value.translation.width,
                    y: start.y + value.translation.height
                ))
            }
            .onEnded { _ in
                dragStartPositions[id] = nil
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
