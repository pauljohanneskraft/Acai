import MCP

extension Value {
    /// MCP requires a tool result's `structuredContent` to be a JSON object, so a top-level-array
    /// report is wrapped in a single-key `items` envelope to stay spec-compliant; an object passes
    /// through unchanged.
    var asStructuredContent: Value {
        if case .object = self { return self }
        return .object(["items": self])
    }
}
