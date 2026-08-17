import MCP

/// `.json` reports render as pretty-printed text plus `structuredContent`; `.content` (a diagram's
/// source text, or a PNG) passes through to the client unchanged.
enum ToolOutput: Sendable {
    case json(Value)
    case content([Tool.Content])
}
