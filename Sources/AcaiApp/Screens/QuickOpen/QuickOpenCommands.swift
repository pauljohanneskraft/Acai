import SwiftUI

/// ⌘L for Quick Open, from the Mac's menu bar or an iPad's hardware keyboard, in the File menu where
/// Xcode keeps Open Quickly. Acts on a `QuickOpenPresenter` it doesn't own, since a `Commands` menu
/// item lives outside any view hierarchy — see that type for where each platform's presenter comes from.
struct QuickOpenCommands: Commands {
    #if os(macOS)
    @FocusedObject private var presenter: QuickOpenPresenter?
    #else
    @EnvironmentObject private var scenePresenter: QuickOpenPresenter
    private var presenter: QuickOpenPresenter? { scenePresenter }
    #endif

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(.app("View.QuickOpenCommands.QuickOpen")) {
                presenter?.isPresented = true
            }
            .keyboardShortcut(.quickOpen)
            .disabled(presenter == nil)
        }
    }
}
