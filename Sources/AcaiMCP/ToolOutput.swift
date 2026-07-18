import MCP

/// What a tool hands back to the registry. Most tools return structured JSON (`.json`) — the registry
/// renders it as pretty-printed text *and* attaches it as `structuredContent`. Diagram/image tools
/// return ready-made MCP content (`.content`) — a diagram's source text, or a PNG the agent can see —
/// which the registry passes through unchanged.
enum ToolOutput: Sendable {
    case json(Value)
    case content([Tool.Content])
}
