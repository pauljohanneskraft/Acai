import SwiftUI

/// Toolbar undo/redo buttons bound to a `CanvasInteraction` model. `onChange` runs after each
/// undo/redo so the view can persist (it owns the canvas scale/offset).
struct UndoRedoToolbarButtons<Model: CanvasInteraction>: View {
    @ObservedObject var model: Model
    let onChange: () -> Void

    var body: some View {
        Button {
            model.undo()
            onChange()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .disabled(!model.canUndo)
        .help("Undo (⌘Z)")

        Button {
            model.redo()
            onChange()
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .disabled(!model.canRedo)
        .help("Redo (⇧⌘Z)")
    }
}

extension View {
    /// Hidden buttons that capture ⌘Z / ⇧⌘Z and route them to the model's undo/redo. `enabled`
    /// lets a view yield the shortcut to native text-field undo while a field is focused.
    func undoRedoKeyboardShortcuts<Model: CanvasInteraction>(
        model: Model,
        enabled: Bool = true,
        onChange: @escaping () -> Void
    ) -> some View {
        background {
            Group {
                Button("") {
                    model.undo()
                    onChange()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!enabled)

                Button("") {
                    model.redo()
                    onChange()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!enabled)
            }
            .hidden()
        }
    }
}
