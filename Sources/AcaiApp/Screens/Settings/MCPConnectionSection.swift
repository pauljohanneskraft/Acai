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
            Text("Açaí's MCP server exposes this same read-only analysis engine — quality "
                + "findings, metrics, call graphs, and diagrams — as MCP tools, so Claude Desktop "
                + "or Claude Code can query your codebases directly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if locator.installedBinaryPath != nil {
                Label("Found an installed server at \(resolvedBinaryPath).", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("mcp.installedLabel")
            } else {
                Label(
                    "No installed acai-mcp binary was found. Build one with "
                        + "\"swift build --product AcaiMCP\", then run Scripts/mcp_install.sh to "
                        + "install it at the path below — or edit the snippet to point at "
                        + ".build/debug/AcaiMCP for a local build.",
                    systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("mcp.notInstalledLabel")
            }

            Text(snippet.json)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("mcp.configSnippet")

            Text("Paste this under \"mcpServers\" in Claude Desktop's claude_desktop_config.json "
                + "or Claude Code's MCP config.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button("Copy") {
                copyToClipboard(snippet.json)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("mcp.copyButton")
            .accessibilityLabel("Copy MCP server configuration")
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
#endif
