import Foundation

/// Formats the `mcpServers` JSON block that both Claude Desktop's `claude_desktop_config.json`
/// and Claude Code's own MCP config expect.
struct MCPServerConfigSnippet {
    let serverName: String
    let binaryPath: String
    var arguments: [String] = []

    /// Built via `JSONSerialization`, not string interpolation, so `binaryPath` is always escaped.
    var json: String {
        var serverConfig: [String: Any] = ["command": binaryPath]
        if !arguments.isEmpty {
            serverConfig["args"] = arguments
        }
        let payload: [String: Any] = ["mcpServers": [serverName: serverConfig]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}
