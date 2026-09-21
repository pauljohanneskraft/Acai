import SwiftUI

#if os(macOS)
/// macOS's ⌘K entry point for Quick Open — matches Xcode/every other developer tool's
/// convention. Acts on the key window's `QuickOpenPresenter`. iPad binds the same shortcut on
/// `ProjectBrowserView` itself, as its other hardware-keyboard shortcuts are bound.
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
#endif
