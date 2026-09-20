import SwiftUI

/// macOS's `Settings` scene content (⌘,) — a real Settings scene with Accounts, MCP, and Licenses
/// sections. General (diagram theme) is a separate, not-yet-built pane (Repositories deliberately
/// stays in the sidebar instead, to avoid duplicating scope), so a `TabView` isn't needed yet for
/// a single scrolling pane.
struct SettingsView: View {
    var body: some View {
        Form {
            Section(.app("View.SettingsView.GitHubAccount")) {
                GitHubAccountSection()
            }
            #if os(macOS)
            Section(.app("View.SettingsView.ConnectViaMCP")) {
                MCPConnectionSection()
            }
            #endif
            Section(.app("View.SettingsView.Licenses")) {
                LicensesSection()
            }
        }
        .formStyle(.grouped)
        // `minWidth`/`idealWidth`, not a fixed `width`: at the default text size the window sizes
        // to 420pt exactly as before, but a fixed width left no room to grow into at the largest
        // accessibility text sizes, where rows need more than 420pt to stay legible.
        .frame(minWidth: 420, idealWidth: 420)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .accessibilityIdentifier("settings.accountsPane")
    }
}
