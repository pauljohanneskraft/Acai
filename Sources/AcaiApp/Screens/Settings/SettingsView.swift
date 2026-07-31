import SwiftUI

/// macOS's `Settings` scene content (⌘,) — a real Settings scene with an Accounts pane.
/// Currently just the Accounts pane: General (diagram theme) and Licenses are separate,
/// not-yet-built panes (Repositories deliberately stays in the sidebar instead, to avoid
/// duplicating scope), so a `TabView` isn't needed yet for exactly one pane — adding one is a
/// small, additive change once a second pane actually exists.
struct SettingsView: View {
    var body: some View {
        Form {
            Section("GitHub Account") {
                GitHubAccountSection()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .accessibilityIdentifier("settings.accountsPane")
    }
}
