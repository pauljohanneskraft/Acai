import SwiftUI

/// Quick Open's `KeyboardShortcutReference.quickOpen` — ⌘K on the Mac, ⇧⌘O on iPad.
///
/// The Mac keeps the item in the Edit menu, acting on the key window's presenter. iPad puts it
/// beside the Help items, on the one scene's presenter, mirroring `KeyboardShortcutCommands` —
/// `CommandGroup(after: .help)` is the only placement whose shortcut iPadOS 26 has been observed to
/// fire here. A menu item after `.textEditing` and after `.newItem`, a `CommandMenu` of the app's
/// own, a zero-opacity button in the view's background and a visible toolbar button were each tried
/// and none of them reached the keyboard.
struct QuickOpenCommands: Commands {
    #if os(macOS)
    @FocusedObject private var presenter: QuickOpenPresenter?
    #else
    @EnvironmentObject private var presenter: QuickOpenPresenter
    #endif

    var body: some Commands {
        #if os(macOS)
        CommandGroup(after: .textEditing) { QuickOpenMenuButton(presenter: presenter) }
        #else
        // iPadOS keeps its own Help items, so this goes beside them rather than replacing them.
        CommandGroup(after: .help) { QuickOpenMenuButton(presenter: presenter) }
        #endif
    }
}

/// Takes the presenter as a plain value: a `Commands` struct's own property wrappers are not in
/// scope for the button's action, which is why `KeyboardShortcutCommands` does the same.
private struct QuickOpenMenuButton: View {
    let presenter: QuickOpenPresenter?

    var body: some View {
        Button(.app("View.QuickOpenCommands.QuickOpen")) {
            presenter?.isPresented = true
        }
        .keyboardShortcut(.quickOpen)
        .disabled(presenter == nil)
    }
}
