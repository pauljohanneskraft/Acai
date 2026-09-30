import SwiftUI

/// "Keyboard Shortcuts" reference panel, grouped by context. Help menu (⌘/) everywhere; iPad/iPhone
/// also reach it from the sidebar toolbar's overflow menu.
struct KeyboardShortcutsPanel: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(KeyboardShortcutReference.groups) { group in
                    Section {
                        ForEach(group.shortcuts) { shortcut in
                            HStack {
                                Text(localized: shortcut.name)
                                Spacer()
                                Text(verbatim: shortcut.symbol)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                        }
                    } header: {
                        Text(localized: group.title)
                    }
                }
            }
            .accessibilityIdentifier("keyboardShortcuts.panel")
            .navigationTitle(.app("View.KeyboardShortcutsPanel.KeyboardShortcuts"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.KeyboardShortcutsPanel.Done")) { dismiss() }
                        .accessibilityIdentifier("keyboardShortcuts.doneButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}

#if os(macOS)
/// Replaces macOS's default Help item, which otherwise just points at a nonexistent Help Book, and
/// opens the panel as its own window. Off macOS the same item comes from `HelpMenuCommands`, which
/// owns the one Help group iPadOS builds, and the panel is `ProjectBrowserView`'s sheet.
struct KeyboardShortcutCommands: Commands {
    /// The `WindowGroup(id:)` this command opens — declared once here so the command and the scene
    /// registration in `AcaiRootScene` can't drift apart.
    static let windowID = "keyboardShortcuts"

    @EnvironmentObject private var presenter: KeyboardShortcutsPresenter

    var body: some Commands {
        CommandGroup(replacing: .help) {
            KeyboardShortcutsHelpMenuButton(presenter: presenter)
        }
    }
}
#endif

struct KeyboardShortcutsHelpMenuButton: View {
    let presenter: KeyboardShortcutsPresenter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(.app("View.KeyboardShortcutsHelpMenuButton.KeyboardShortcuts")) {
            #if os(macOS)
            openWindow(id: KeyboardShortcutCommands.windowID)
            #else
            presenter.isPresented = true
            #endif
        }
        .keyboardShortcut(.keyboardShortcuts)
    }
}
