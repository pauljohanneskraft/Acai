import SwiftUI

/// macOS's `Settings` scene content (⌘,) — one scrolling pane with Accounts, Appearance, MCP and
/// Licenses sections. Repositories deliberately stays in the sidebar, to avoid duplicating scope.
struct SettingsView: View {
    var body: some View {
        Form {
            Section(.app("View.SettingsView.GitHubAccount")) {
                GitHubAccountSection()
            }
            Section(.app("View.SettingsView.Appearance")) {
                DiagramThemePicker()
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
        //
        // The height is bounded and the form scrolls instead of sizing the window to its content:
        // grown to fit the licence list, the window reached past the bottom of the screen, and a
        // sheet presented over it centres on the window rather than the display — which put the
        // sign-out confirmation's buttons below the visible area, out of reach entirely.
        .frame(minWidth: 420, idealWidth: 420, minHeight: 320, idealHeight: 560)
        .padding()
        .accessibilityIdentifier("settings.accountsPane")
    }
}
