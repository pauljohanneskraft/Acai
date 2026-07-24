import SwiftUI

/// "Keyboard Shortcuts" reference panel (B56): every shortcut the app currently wires up, grouped
/// by context. macOS: opened from the Help menu (⌘⇧/, i.e. ⌘?). iPad/iPhone: opened from the
/// sidebar toolbar's overflow menu.
struct KeyboardShortcutsPanel: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(KeyboardShortcutReference.groups) { group in
                    Section(group.title) {
                        ForEach(group.shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.name)
                                Spacer()
                                Text(shortcut.symbol)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Keyboard Shortcuts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}

#if os(macOS)
/// Adds a "Keyboard Shortcuts" item to the Help menu (replacing macOS's default, which otherwise
/// just points at a nonexistent Help Book), opening the panel as its own window.
struct KeyboardShortcutCommands: Commands {
    /// The `WindowGroup(id:)` this command opens — declared once here so the command and the scene
    /// registration in `AcaiRootScene` can't drift apart.
    static let windowID = "keyboardShortcuts"

    var body: some Commands {
        CommandGroup(replacing: .help) {
            KeyboardShortcutsHelpMenuButton()
        }
    }
}

private struct KeyboardShortcutsHelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Keyboard Shortcuts") {
            openWindow(id: KeyboardShortcutCommands.windowID)
        }
        .keyboardShortcut("/", modifiers: [.command, .shift])
    }
}
#endif
