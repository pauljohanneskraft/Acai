import SwiftUI

/// ⌘K for Quick Open — matches Xcode/every other developer tool's convention. Acts on a
/// `QuickOpenPresenter` it doesn't own, since a `Commands` menu item lives outside any view
/// hierarchy — see that type for where each platform's presenter comes from.
///
/// The Mac keeps the item in the Edit menu. iPadOS builds only some of the system menus SwiftUI's
/// `CommandGroup` placements target, and a shortcut in one it leaves out never reaches the keyboard:
/// on iPadOS 26 the same button went unhandled after `.textEditing` and after `.newItem`, while ⌘/
/// after `.help` fires. A menu the app declares itself is always built, so iPad gets one of its own.
struct QuickOpenCommands: Commands {
    #if os(macOS)
    @FocusedObject private var presenter: QuickOpenPresenter?
    #else
    @EnvironmentObject private var scenePresenter: QuickOpenPresenter
    private var presenter: QuickOpenPresenter? { scenePresenter }
    #endif

    var body: some Commands {
        #if os(macOS)
        CommandGroup(after: .textEditing) { quickOpenItem }
        #else
        CommandMenu(Text(localized: .app("View.QuickOpenCommands.Navigation"))) { quickOpenItem }
        #endif
    }

    private var quickOpenItem: some View {
        Button(.app("View.QuickOpenCommands.QuickOpen")) {
            presenter?.isPresented = true
        }
        .keyboardShortcut(.quickOpen)
        .disabled(presenter == nil)
    }
}
