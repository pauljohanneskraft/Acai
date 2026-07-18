import SwiftUI

extension CanvasInteraction {
    /// Shared, group-aware node-drag gesture used by every diagram canvas: records one undo
    /// checkpoint at the start of a drag, moves the whole selection together, reports the dragged
    /// node's location for edge auto-pan, and commits (persists) on release. Behaviour on the model
    /// it drives (not a free function).
    func nodeDragGesture(
        id: String,
        dragStartPositions: Binding<[String: CGPoint]>,
        activeDragCanvasLocation: Binding<CGPoint?>,
        onCommit: @escaping () -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartPositions.wrappedValue.isEmpty {
                    self.recordUndo()
                    if !self.selectedNodeIDs.contains(id) {
                        self.selectedNodeIDs = [id]
                    }
                    for nodeID in self.selectedNodeIDs {
                        dragStartPositions.wrappedValue[nodeID] = self.nodePosition(nodeID)
                    }
                }
                let tx = value.translation.width
                let ty = value.translation.height
                for nodeID in self.selectedNodeIDs {
                    guard let start = dragStartPositions.wrappedValue[nodeID] else { continue }
                    self.moveNode(nodeID, to: CGPoint(x: start.x + tx, y: start.y + ty))
                }
                if let start = dragStartPositions.wrappedValue[id] {
                    activeDragCanvasLocation.wrappedValue = CGPoint(x: start.x + tx, y: start.y + ty)
                }
            }
            .onEnded { _ in
                dragStartPositions.wrappedValue = [:]
                activeDragCanvasLocation.wrappedValue = nil
                onCommit()
            }
    }
}

extension View {
    /// The shared node interaction for every layout-backed diagram canvas: cmd-click extends the
    /// selection (a plain click replaces it), and a group-aware drag moves the whole selection,
    /// committing on release.
    @MainActor
    func diagramNodeInteraction<Model: CanvasInteraction>(
        id: String,
        model: Model,
        dragStartPositions: Binding<[String: CGPoint]>,
        activeDragCanvasLocation: Binding<CGPoint?>,
        onCommit: @escaping () -> Void
    ) -> some View {
        onTapGesture {
            #if os(macOS)
            let extending = NSEvent.modifierFlags.contains(.command)
            #else
            let extending = false
            #endif
            model.selectNode(id, extending: extending)
        }
        .highPriorityGesture(model.nodeDragGesture(
            id: id,
            dragStartPositions: dragStartPositions,
            activeDragCanvasLocation: activeDragCanvasLocation,
            onCommit: onCommit
        ))
    }
}

/// A reusable bottom-right resize handle that resizes a node while keeping its top-left fixed
/// (the node center moves by half the size delta). Records one undo checkpoint per drag.
struct CanvasResizeHandle<Model: CanvasInteraction>: View {
    let id: String
    @ObservedObject var model: Model
    let position: CGPoint
    let size: CGSize
    @Binding var activeResizeState: DiagramResizeState?
    let onCommit: () -> Void

    var minWidth: CGFloat = 80
    var minHeight: CGFloat = 50
    var handleSize: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            #if os(macOS)
            .cursorOnHover(.closedHand)
            #endif
            .frame(width: handleSize, height: handleSize)
            .contentShape(Rectangle())
            .position(x: position.x + size.width / 2, y: position.y + size.height / 2)
            .gesture(resizeGesture)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeResizeState == nil {
                    model.recordUndo()
                    activeResizeState = DiagramResizeState(
                        startSize: model.effectiveSize(for: id),
                        startPosition: model.nodePosition(id) ?? .zero
                    )
                }
                guard let state = activeResizeState else { return }
                let newW = max(minWidth, state.startSize.width + value.translation.width)
                let newH = max(minHeight, state.startSize.height + value.translation.height)
                let dw = newW - state.startSize.width
                let dh = newH - state.startSize.height
                model.resizeNode(id, width: newW, height: newH)
                model.moveNode(id, to: CGPoint(
                    x: state.startPosition.x + dw / 2,
                    y: state.startPosition.y + dh / 2
                ))
            }
            .onEnded { _ in
                activeResizeState = nil
                onCommit()
            }
    }
}
