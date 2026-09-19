import SwiftUI

/// iPad/iPhone's Settings surface — same content as macOS's `Settings` scene
/// (`SettingsView`), presented as a sheet since neither platform has a `Settings` scene to reach
/// via ⌘,.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showKeyboardShortcuts = false

    var body: some View {
        NavigationStack {
            Form {
                Section(.app("View.SettingsSheet.Appearance")) {
                    DiagramThemePicker()
                }
                Section(.app("View.SettingsSheet.GitHubAccount")) {
                    GitHubAccountSection()
                }
                Section {
                    Button {
                        showKeyboardShortcuts = true
                    } label: {
                        Label(.app("View.SettingsSheet.KeyboardShortcuts"), systemImage: "keyboard")
                    }
                    .accessibilityIdentifier("settings.keyboardShortcutsButton")
                }
                Section(.app("View.SettingsSheet.Licenses")) {
                    LicensesSection()
                }
            }
            .navigationTitle(.app("View.SettingsSheet.Settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.SettingsSheet.Done")) { dismiss() }
                        .accessibilityIdentifier("settings.doneButton")
                }
            }
        }
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutsPanel()
        }
        .accessibilityIdentifier("settings.sheet")
    }
}
