import SwiftUI

/// iPad/iPhone's Settings surface — same content as macOS's `Settings` scene
/// (`SettingsView`), presented as a sheet since neither platform has a `Settings` scene to reach
/// via ⌘,. Opened from the sidebar toolbar's gear icon (`ProjectBrowserView`) or from
/// `NewCodebaseSheet`'s "Sign in to GitHub in Settings" prompt, both via the shared
/// `SettingsPresenter`.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub Account") {
                    GitHubAccountSection()
                }
                Section("Licenses") {
                    LicensesSection()
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.doneButton")
                }
            }
        }
        .accessibilityIdentifier("settings.sheet")
    }
}
