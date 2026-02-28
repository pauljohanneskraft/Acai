import SwiftUI
import UMLCore

// MARK: - Canvas Layers & Node Interaction

extension CustomDiagramEditorView {

    // MARK: - Edge Layer

    var edgeLayer: some View {
        ForEach(viewModel.edges) { edge in
            let sourceRect = viewModel.nodeRect(edge.sourceNodeID)
            let targetRect = viewModel.nodeRect(edge.targetNodeID)
            
            RelationshipEdgeView(
                kind: edge.kind,
                sourceRect: sourceRect,
                targetRect: targetRect
            )
            .onTapGesture(count: 2) {
                viewModel.selectedEdgeID = (viewModel.selectedEdgeID == edge.id) ? nil : edge.id
                sidebarTab = .inspector
                showSidebar = true
            }
            .onTapGesture(count: 1) {
                viewModel.selectedEdgeID = (viewModel.selectedEdgeID == edge.id) ? nil : edge.id
            }
        }
    }

    // MARK: - Container Node Layer (lowest z-level)

    var containerNodeLayer: some View {
        ForEach(viewModel.nodes.filter(\.isResizable).sorted(by: { $0.drawOrder < $1.drawOrder })) { node in
            nodeView(for: node)
        }
    }

    // MARK: - Regular Node Layer (highest z-level)

    var regularNodeLayer: some View {
        ForEach(viewModel.nodes.filter({ !$0.isResizable }).sorted(by: { $0.drawOrder < $1.drawOrder })) { node in
            nodeView(for: node)
        }
    }

    func nodeView(for node: CustomDiagram.Node) -> some View {
        let pos = CGPoint(x: node.positionX, y: node.positionY)
        let size = viewModel.nodeSize(node.id)
        let selected = viewModel.selectedNodeIDs.contains(node.id)

        return nodeContent(node: node, size: size, isSelected: selected)
            .position(pos)
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
                    Label("Edit", systemImage: "pencil")
                }

                Divider()

                Button {
                    viewModel.moveNodeHigher(node.id)
                } label: {
                    Label("Move Higher", systemImage: "chevron.up")
                }

                Button {
                    viewModel.moveNodeLower(node.id)
                } label: {
                    Label("Move Lower", systemImage: "chevron.down")
                }

                Divider()

                Button(role: .destructive) {
                    viewModel.removeNode(node.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    func nodeContent(node: CustomDiagram.Node, size: CGSize, isSelected: Bool) -> some View {
        if node.isResizable {
            CustomNodeView(node: node, isSelected: isSelected, size: size)
                .frame(width: size.width, height: size.height)
                // Disable hit testing on the outer frame edges so resize handles
                // in the layer above can receive hover / drag.
                .contentShape(Rectangle().inset(by: 6))
        } else {
            CustomNodeView(node: node, isSelected: isSelected, size: nil)
                .fixedSize()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: NodeSizePreferenceKey.self,
                            value: [node.id.uuidString: geo.size]
                        )
                    }
                )
        }
    }

    // MARK: - Resize Handle Layer

    var resizeHandleLayer: some View {
        ForEach(viewModel.nodes.filter { $0.isResizable }) { node in
            let pos = CGPoint(x: node.positionX, y: node.positionY)
            let size = viewModel.nodeSize(node.id)
            edgeResizeHandles(for: node.id, at: pos, size: size)
        }
    }

    func edgeResizeHandles(for id: UUID, at position: CGPoint, size: CGSize) -> some View {
        let handleSize: CGFloat = 16
        return Rectangle()
            .fill(Color.clear)
            #if os(macOS)
            .cursorOnHover(.closedHand)
            #endif
            .frame(width: handleSize, height: handleSize)
            .contentShape(Rectangle())
            .position(x: position.x + size.width / 2, y: position.y + size.height / 2)
            .gesture(edgeResizeGesture(for: id))
    }

    func edgeResizeGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeResizeState == nil {
                    activeResizeState = ResizeState(
                        startSize: viewModel.nodeSize(id),
                        startPosition: viewModel.nodePosition(id) ?? .zero
                    )
                }
                guard let state = activeResizeState else { return }
                let minW: CGFloat = 80, minH: CGFloat = 50

                let newW = max(minW, state.startSize.width + value.translation.width)
                let newH = max(minH, state.startSize.height + value.translation.height)
                let dw = newW - state.startSize.width
                let dh = newH - state.startSize.height
                viewModel.resizeNode(id, width: newW, height: newH)
                viewModel.moveNode(id, to: CGPoint(
                    x: state.startPosition.x + dw / 2,
                    y: state.startPosition.y + dh / 2
                ))
            }
            .onEnded { _ in
                activeResizeState = nil
                viewModel.save()
            }
    }

    // MARK: - Node Dragging (Group)

    func nodeDragGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartPositions.isEmpty {
                    if !viewModel.selectedNodeIDs.contains(id) {
                        viewModel.selectedNodeIDs = [id]
                    }
                    for nodeID in viewModel.selectedNodeIDs {
                        dragStartPositions[nodeID] = viewModel.nodePosition(nodeID)
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
                viewModel.save()
            }
    }
}
