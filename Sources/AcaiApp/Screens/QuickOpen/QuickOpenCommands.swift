import SwiftUI

/// Quick Open's `KeyboardShortcutReference.quickOpen`, in the Edit menu. macOS acts on the key
/// window's presenter; off macOS there is one scene, so the item reads the scene's presenter.
struct QuickOpenCommands: Commands {
    #if os(macOS)
    @FocusedObject private var presenter: QuickOpenPresenter?
    #else
    @EnvironmentObject private var presenter: QuickOpenPresenter
    #endif

    var body: some Commands {
        CommandGroup(after: .textEditing) { QuickOpenMenuButton(presenter: presenter) }
    }
}

/// Takes the presenter as a plain value: a `Commands` struct's own property wrappers are not in
/// scope for the button's action, which is why `KeyboardShortcutsHelpMenuButton` does the same.
struct QuickOpenMenuButton: View {
    let presenter: QuickOpenPresenter?

    var body: some View {
        Button(.app("View.QuickOpenCommands.QuickOpen")) {
            presenter?.isPresented = true
        }
        .keyboardShortcut(.quickOpen)
        .disabled(presenter == nil)
    }
}
