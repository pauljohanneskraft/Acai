import SwiftUI

/// ⌘K for Quick Open, from the Mac's menu bar or an iPad's hardware keyboard — matches
/// Xcode/every other developer tool's convention. Acts on a `QuickOpenPresenter` it doesn't own, since
/// a `Commands` menu item lives outside any view hierarchy — see that type for where each platform's
/// presenter comes from.
struct QuickOpenCommands: Commands {
    #if os(macOS)
    @FocusedObject private var presenter: QuickOpenPresenter?
    #else
    @EnvironmentObject private var scenePresenter: QuickOpenPresenter
    private var presenter: QuickOpenPresenter? { scenePresenter }
    #endif

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
