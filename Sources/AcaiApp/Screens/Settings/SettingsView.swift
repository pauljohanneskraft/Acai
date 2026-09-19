import SwiftUI

/// macOS's `Settings` scene content (⌘,) — one scrolling pane with Appearance, Accounts, MCP and
/// Licenses sections. Repositories deliberately stays in the sidebar, to avoid duplicating scope.
struct SettingsView: View {
    var body: some View {
        Form {
            Section(.app("View.SettingsView.Appearance")) {
                DiagramThemePicker()
            }
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
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .accessibilityIdentifier("settings.accountsPane")
    }
}
