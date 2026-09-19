import SwiftUI

/// Maps an Apple Pencil double-tap (or squeeze) to undo on a diagram canvas. The canvas has no
/// eraser or palette to switch to, so undo stands in for any action the user chose in Settings —
/// except "Ignore", and a system shortcut, which the system runs itself.
struct PencilDoubleTapUndo<Model: CanvasInteraction>: ViewModifier {
    let model: Model
    let enabled: Bool
    let onChange: () -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 17.5, *) {
            content.modifier(PencilDoubleTapUndoHandler(model: model, enabled: enabled, onChange: onChange))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS)
@available(iOS 17.5, *)
private struct PencilDoubleTapUndoHandler<Model: CanvasInteraction>: ViewModifier {
    let model: Model
    let enabled: Bool
    let onChange: () -> Void
    @Environment(\.preferredPencilDoubleTapAction) private var preferredAction

    func body(content: Content) -> some View {
        content.onPencilDoubleTap { _ in
            guard enabled, preferredAction != .ignore, preferredAction != .runSystemShortcut else { return }
            model.undo()
            onChange()
        }
    }
}
#endif
