import SwiftUI

/// iPad/iPhone's Settings surface — same content as macOS's `Settings` scene
/// (`SettingsView`), presented as a sheet since neither platform has a `Settings` scene to reach
/// via ⌘,.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(.app("View.SettingsSheet.GitHubAccount")) {
                    GitHubAccountSection()
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
        .accessibilityIdentifier("settings.sheet")
    }
}
