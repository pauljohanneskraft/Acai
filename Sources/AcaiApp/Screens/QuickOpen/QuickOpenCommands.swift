import SwiftUI

/// macOS's ⌘K entry point for Quick Open — matches Xcode/every other developer tool's
/// convention. Toggles the shared `QuickOpenPresenter` rather than owning its own state, since a
/// `Commands` menu item lives outside the view hierarchy `ProjectBrowserView`'s own `@State` could
/// reach — see that type's doc comment.
struct QuickOpenCommands: Commands {
    @EnvironmentObject private var presenter: QuickOpenPresenter

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(.app("View.QuickOpenCommands.QuickOpen")) {
                presenter.isPresented = true
            }
            .keyboardShortcut("k", modifiers: .command)
        }
    }
}
