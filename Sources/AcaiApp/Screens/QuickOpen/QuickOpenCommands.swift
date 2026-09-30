import SwiftUI

#if os(macOS)
/// Quick Open's `KeyboardShortcutReference.quickOpen` — ⌘K, in the Edit menu, acting on the key
/// window's presenter. Off macOS the item comes from `HelpMenuCommands` instead.
struct QuickOpenCommands: Commands {
    @FocusedObject private var presenter: QuickOpenPresenter?

    var body: some Commands {
        CommandGroup(after: .textEditing) { QuickOpenMenuButton(presenter: presenter) }
    }
}
#endif

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
