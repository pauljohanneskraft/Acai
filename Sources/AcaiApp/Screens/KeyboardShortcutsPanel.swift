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

/// macOS replaces its own default Help item, which otherwise just points at a nonexistent Help Book,
/// and opens the panel as its own window. iPadOS keeps its Help items, so the item goes beside them
/// and the panel is `ProjectBrowserView`'s sheet.
///
/// This is deliberately the app's only addition to the Help menu. iPadOS 26 delivered ⌘/ from here
/// while it was, and stopped once a second shortcut shared the group — so another command that needs
/// a key off macOS belongs in its own menu, not beside this one.
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

struct KeyboardShortcutsHelpMenuButton: View {
    let presenter: KeyboardShortcutsPresenter
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

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
