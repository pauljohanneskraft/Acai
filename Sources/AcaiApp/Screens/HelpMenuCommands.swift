import SwiftUI

#if !os(macOS)
/// Every menu item the app adds beside iPadOS's own Help items.
///
/// `CommandGroup(after: .help)` is the only placement whose shortcut iPadOS 26 has been observed to
/// fire — a menu item after `.textEditing` and after `.newItem`, a `CommandMenu` of the app's own, a
/// zero-opacity button in the view's background and a visible toolbar button each failed to reach
/// the keyboard. A scene builds only the last of several `CommandGroup(after: .help)` declarations,
/// so both items are declared here together rather than one per command type: a second group would
/// silently take the shortcut of the first.
struct HelpMenuCommands: Commands {
    @EnvironmentObject private var keyboardShortcutsPresenter: KeyboardShortcutsPresenter
    @EnvironmentObject private var quickOpenPresenter: QuickOpenPresenter

    var body: some Commands {
        CommandGroup(after: .help) {
            KeyboardShortcutsHelpMenuButton(presenter: keyboardShortcutsPresenter)
            QuickOpenMenuButton(presenter: quickOpenPresenter)
        }
    }
}
#endif
