import SwiftUI

/// "Keyboard Shortcuts" reference panel, grouped by context. Help menu (⇧⌘/) everywhere; iPad/iPhone
/// also reach it from the sidebar toolbar's overflow menu.
struct KeyboardShortcutsPanel: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(KeyboardShortcutReference.allGroups) { group in
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

/// Adds a "Keyboard Shortcuts" item to the Help menu (replacing macOS's default, which otherwise
/// just points at a nonexistent Help Book). macOS opens the panel as its own window; iPad/iPhone
/// present it as `ProjectBrowserView`'s sheet.
struct KeyboardShortcutCommands: Commands {
    /// The `WindowGroup(id:)` this command opens on macOS — declared once here so the command and the
    /// scene registration in `AcaiRootScene` can't drift apart.
    static let windowID = "keyboardShortcuts"

    @EnvironmentObject private var presenter: KeyboardShortcutsPresenter

    var body: some Commands {
        #if os(macOS)
        CommandGroup(replacing: .help) {
            KeyboardShortcutsHelpMenuButton(presenter: presenter)
        }
        #else
        CommandGroup(after: .help) {
            KeyboardShortcutsHelpMenuButton(presenter: presenter)
        }
        #endif
    }
}

private struct KeyboardShortcutsHelpMenuButton: View {
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
