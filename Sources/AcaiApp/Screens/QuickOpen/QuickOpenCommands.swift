import SwiftUI

/// The Mac's ⌘K entry point for Quick Open — matches Xcode/every other developer tool's
/// convention. Acts on the key window's `QuickOpenPresenter`.
///
/// iPad binds the same shortcut on the Quick Open toolbar button in `ProjectBrowserView` instead of
/// here. A `Commands` menu item never fired it on iPadOS 26 — not after `.textEditing`, not after
/// `.newItem`, and not from a `CommandMenu` of the app's own — while ⌘/ after `.help` does, so only
/// some of the menus these placements target are built there. A visible, enabled button in the view
/// hierarchy has no such gaps; an invisible one does, which is why it is that button and not a
/// dedicated hidden one.
struct QuickOpenCommands: Commands {
    @FocusedObject private var presenter: QuickOpenPresenter?

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(.app("View.QuickOpenCommands.QuickOpen")) {
                presenter?.isPresented = true
            }
            .keyboardShortcut(.quickOpen)
            .disabled(presenter == nil)
        }
    }
}
