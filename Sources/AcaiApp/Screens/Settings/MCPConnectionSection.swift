#if os(macOS)
import SwiftUI
import AppKit

struct MCPConnectionSection: View {
    private let locator = MCPBinaryLocator()

    private var resolvedBinaryPath: String {
        locator.installedBinaryPath ?? "/usr/local/bin/acai-mcp"
    }

    private var snippet: MCPServerConfigSnippet {
        MCPServerConfigSnippet(serverName: "acai", binaryPath: resolvedBinaryPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.app("View.MCPConnectionSection.AçaíSMCPServer"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if locator.installedBinaryPath != nil {
                Label(
                    .app("View.MCPConnectionSection.FoundInstalledServer \(resolvedBinaryPath)"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityIdentifier("mcp.installedLabel")
            } else {
                Label(.app("View.MCPConnectionSection.NoInstalledBinaryFound"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("mcp.notInstalledLabel")
            }

            Text(verbatim: snippet.json)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("mcp.configSnippet")

            Text(.app("View.MCPConnectionSection.PasteUnderMcpServersClaude"))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button(.app("View.MCPConnectionSection.Copy")) {
                copyToClipboard(snippet.json)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("mcp.copyButton")
            .accessibilityLabel(.app("View.MCPConnectionSection.CopyMCPServerConfiguration"))
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
#endif
