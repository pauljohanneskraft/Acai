import SwiftUI

/// `InfiniteCanvas` pre-wired with the standard diagram interactions (marquee → select,
/// background tap → clear, auto-pan → move selection). Each diagram view supplies only its
/// scale/offset bindings, the active-drag location for edge auto-pan, and its node/edge content.
struct PannableCanvas<Model: CanvasInteraction, Content: View>: View {
    @ObservedObject var model: Model
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint
    /// The canvas-space location of the node currently under the pointer during a drag, used to
    /// trigger edge auto-pan. `nil` when no drag is in progress.
    var activeDragCanvasLocation: CGPoint?
    var autoPanController: EdgeAutoPanController
    @ViewBuilder var content: () -> Content

    var body: some View {
        InfiniteCanvas(
            scale: $scale,
            offset: $offset,
            onSelectionRect: { rect in
                model.selectNodes(in: rect)
            },
            onBackgroundTap: {
                model.clearSelection()
            },
            autoPanDragLocation: activeDragCanvasLocation,
            onAutoPanDelta: { delta in
                for id in model.selectedNodeIDs {
                    guard let pos = model.nodePosition(id) else { continue }
                    model.moveNode(id, to: CGPoint(x: pos.x + delta.width, y: pos.y + delta.height))
                }
            },
            autoPanController: autoPanController,
            content: content
        )
    }
}
