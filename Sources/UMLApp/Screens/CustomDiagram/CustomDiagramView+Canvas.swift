import SwiftUI
import UMLCore
import UMLDiagram
import UMLRender

// MARK: - Canvas Layers & Node Interaction

extension CustomDiagramView {

    // MARK: - Edge Layer

    var edgeLayer: some View {
        // Sequence messages are drawn by `sequenceLayer` through the shared layout.
        let messageEdgeIDs = Set(viewModel.messageEdges.map(\.id))
        return ForEach(viewModel.edges.filter { !messageEdgeIDs.contains($0.id) }) { edge in
            RelationshipEdgeView(
                kind: edge.kind,
                sourceRect: viewModel.nodeRect(edge.sourceNodeID),
                targetRect: viewModel.nodeRect(edge.targetNodeID),
                // Transitions draw their UML `event [guard] / action` label; ordinary
                // relationship edges show their free-form label, when set.
                label: edge.transition?.label ?? edge.label
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

    @ViewBuilder
    var containerNodeLayer: some View {
        let nodes = viewModel.nodes
            .filter(\.isResizable)
            .sorted { $0.drawOrder < $1.drawOrder }
        ForEach(nodes) { node in
            nodeView(for: node)
        }
    }

    // MARK: - Regular Node Layer (highest z-level)

    @ViewBuilder
    var regularNodeLayer: some View {
        // Lifelines and fragments render through the sequence layer, not as free nodes.
        let nodes = viewModel.nodes
            .filter { !$0.isResizable && !viewModel.isLifeline($0.id) && !viewModel.isFragment($0.id) }
            .sorted { $0.drawOrder < $1.drawOrder }
        ForEach(nodes) { node in
            nodeView(for: node)
        }
    }

    // MARK: - Sequence Layer (lifelines + ordered messages)

    /// Renders the diagram's sequence elements — lifelines, execution bars and time-ordered
    /// message arrows — through the same `SequenceLayoutModel` / `SequenceEnsembleView` the
    /// generated sequence view uses, so custom sequence diagrams look identical to generated
    /// ones. Headers stay interactive custom nodes (select, drag, context menu); messages get
    /// tap targets that select their backing edge for the inspector.
    @ViewBuilder
    var sequenceLayer: some View {
        if let layout = viewModel.sequenceLayout {
            let anchorY = viewModel.sequenceAnchorY

            SequenceEnsembleView(layout: layout)
                .offset(y: anchorY)
                .allowsHitTesting(false)

            // Tap targets over each message arrow, selecting the backing edge.
            ForEach(layout.messages) { message in
                messageTapTarget(message, anchorY: anchorY)
            }

            // Selected-fragment highlight + tap targets on the fragment tabs. (Fragment frames
            // themselves are drawn by the ensemble; frame ids are the backing node ids.)
            ForEach(layout.fragments) { fragment in
                if viewModel.selectedNodeIDs.contains(fragment.id) {
                    SequenceFragmentView(fragment: fragment, isSelected: true)
                        .offset(y: anchorY)
                        .allowsHitTesting(false)
                }
                fragmentTapTarget(fragment, anchorY: anchorY)
            }

            // Interactive participant headers.
            ForEach(viewModel.lifelineNodes) { node in
                lifelineHeader(for: node, anchorY: anchorY)
            }
        }
    }

    /// An invisible tap strip over a fragment's operator tab, selecting its backing node.
    /// Sized from the layout's `tabRect` (plus slack) so the whole tab is always clickable,
    /// however long the operator name.
    private func fragmentTapTarget(
        _ fragment: SequenceLayoutModel.FragmentFrame,
        anchorY: CGFloat
    ) -> some View {
        let tab = fragment.tabRect.insetBy(dx: -4, dy: -3)
        return Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            #if os(macOS)
            .cursorOnHover(.pointingHand)
            #endif
            .frame(width: tab.width, height: tab.height)
            .position(x: tab.midX, y: anchorY + tab.midY)
            .onTapGesture(count: 2) {
                viewModel.selectNode(fragment.id, extending: false)
                sidebarTab = .inspector
                showSidebar = true
            }
            .onTapGesture(count: 1) {
                #if os(macOS)
                let extending = NSEvent.modifierFlags.contains(.command)
                #else
                let extending = false
                #endif
                viewModel.selectNode(fragment.id, extending: extending)
            }
    }

    private func messageTapTarget(_ message: SequenceLayoutModel.MessageLayout, anchorY: CGFloat) -> some View {
        let width = max(abs(message.toX - message.fromX), 44)
        let midX = (message.fromX + message.toX) / 2
        let isSelected = viewModel.selectedEdgeID != nil
            && viewModel.messageEdge(forLayoutID: message.id)?.id == viewModel.selectedEdgeID
        return RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            #if os(macOS)
            .cursorOnHover(.pointingHand)
            #endif
            // Cover the label above the arrow as well as the arrow itself.
            .frame(width: width + 16, height: 30)
            .position(x: midX, y: anchorY + message.y - 4)
            .onTapGesture(count: 2) {
                guard let edge = viewModel.messageEdge(forLayoutID: message.id) else { return }
                viewModel.selectedEdgeID = edge.id
                sidebarTab = .inspector
                showSidebar = true
            }
            .onTapGesture(count: 1) {
                guard let edge = viewModel.messageEdge(forLayoutID: message.id) else { return }
                viewModel.selectedEdgeID = (viewModel.selectedEdgeID == edge.id) ? nil : edge.id
            }
    }

    private func lifelineHeader(for node: CustomDiagram.Node, anchorY: CGFloat) -> some View {
        let kind: SequenceDiagram.Participant.Kind =
            if case .lifeline(let k) = node.content { k } else { .object }
        let size = viewModel.nodeSize(node.id)
        // Snap to the shared header row regardless of the node's stored y.
        let position = CGPoint(
            x: node.positionX,
            y: anchorY + SequenceLayoutModel.headerHeight / 2
        )
        return ParticipantHeaderView(
            name: node.name,
            kind: kind,
            isSelected: viewModel.selectedNodeIDs.contains(node.id)
        )
        .frame(width: size.width, height: size.height)
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
            onCommit: { viewModel.save() }
        ))
        .contextMenu {
            nodeContextMenu(for: node)
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
            .highPriorityGesture(canvasNodeDragGesture(
                id: node.id,
                model: viewModel,
                dragStartPositions: $dragStartPositions,
                activeDragCanvasLocation: $activeDragCanvasLocation,
                onCommit: { viewModel.save() }
            ))
            .contextMenu {
                nodeContextMenu(for: node)
            }
    }

    @ViewBuilder
    private func nodeContextMenu(for node: CustomDiagram.Node) -> some View {
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
                .measuredNode(id: node.id)
        }
    }

    // MARK: - Resize Handle Layer

    @ViewBuilder
    var resizeHandleLayer: some View {
        let nodes = viewModel.nodes
            .filter { $0.isResizable }
        ForEach(nodes) { node in
            let pos = CGPoint(x: node.positionX, y: node.positionY)
            let size = viewModel.nodeSize(node.id)
            CanvasResizeHandle(
                id: node.id,
                model: viewModel,
                position: pos,
                size: size,
                activeResizeState: $activeResizeState,
                onCommit: { viewModel.save() }
            )
        }
    }
}
