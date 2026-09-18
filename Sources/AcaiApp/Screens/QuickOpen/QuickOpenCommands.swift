import SwiftUI

/// macOS's ⌘K entry point for Quick Open — matches Xcode/every other developer tool's
/// convention. Acts on the key window's `QuickOpenPresenter`.
struct QuickOpenCommands: Commands {
    @FocusedObject private var presenter: QuickOpenPresenter?

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(.app("View.QuickOpenCommands.QuickOpen")) {
                presenter?.isPresented = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(presenter == nil)
        }
    }
}
