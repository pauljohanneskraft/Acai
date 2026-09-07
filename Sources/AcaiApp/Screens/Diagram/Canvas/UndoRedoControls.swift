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
            Label(.app("View.UndoRedoToolbarButtons.Undo"), systemImage: "arrow.uturn.backward")
        }
        .disabled(!model.canUndo)
        .help(.app("View.UndoRedoToolbarButtons.UndoZ"))
        .accessibilityIdentifier("diagram.undoButton")

        Button {
            model.redo()
            onChange()
        } label: {
            Label(.app("View.UndoRedoToolbarButtons.Redo"), systemImage: "arrow.uturn.forward")
        }
        .disabled(!model.canRedo)
        .help(.app("View.UndoRedoToolbarButtons.RedoZ"))
        .accessibilityIdentifier("diagram.redoButton")
    }
}

/// Toggles a `CanvasInteraction` model's touch-only "Select" mode (see `isMultiSelectActive`).
/// macOS doesn't need this button (it keeps Cmd-click), so callers gate it `#if !os(macOS)`.
struct MultiSelectToggleButton<Model: CanvasInteraction>: View {
    @ObservedObject var model: Model

    var body: some View {
        Button {
            model.isMultiSelectActive.toggle()
        } label: {
            Label(
                .app("View.MultiSelectToggleButton.Select"),
                systemImage: model.isMultiSelectActive ? "checkmark.circle.fill" : "checkmark.circle"
            )
        }
        .help(.app("View.MultiSelectToggleButton.ToggleMultiSelectMode"))
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

    /// The shared lifecycle wiring for every layout-backed diagram view: undo/redo shortcuts, the
    /// navigation title, a one-frame-delayed initial fit, and a save on disappear. The toolbar stays
    /// per-view (each diagram kind has its own buttons).
    @MainActor
    func diagramCanvasLifecycle<Model: CanvasInteraction>(
        title: String,
        model: Model,
        onSave: @escaping () -> Void,
        onCenter: @escaping () -> Void
    ) -> some View {
        undoRedoKeyboardShortcuts(model: model, onChange: onSave)
            .navigationTitle(title)
            #if !os(macOS)
            // A large/automatic title on iPad wastes header height on every diagram screen even
            // when the title is short — these are working canvases, not reading surfaces, so the
            // compact bar is the right default everywhere this lifecycle is used.
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1))
                onCenter()
            }
            .onDisappear { onSave() }
    }
}
