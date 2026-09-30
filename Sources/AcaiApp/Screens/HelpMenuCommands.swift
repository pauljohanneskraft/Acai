import SwiftUI

#if !os(macOS)
/// Every menu item the app adds beside iPadOS's own Help items.
///
/// iPadOS 26 delivers a shortcut only from `CommandGroup(after: .help)`, and a scene builds only the
/// last of several declarations of that group — so every item belongs here together rather than one
/// per command type, where a second group would silently take the first's shortcut. Worth re-checking
/// on each iPadOS release, since Help is an odd home for anything but the panel.
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
