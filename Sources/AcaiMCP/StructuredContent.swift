import MCP

extension Value {
    /// MCP requires a tool result's `structuredContent` to be a JSON object. A tool whose report is
    /// a top-level array (cycles, smells, inspect, callcycles, enums) is wrapped in a single-key
    /// `items` envelope so it stays spec-compliant and passes client validation; an object passes
    /// through unchanged. The text channel keeps the raw value (byte-identical to the CLI's JSON).
    var asStructuredContent: Value {
        if case .object = self { return self }
        return .object(["items": self])
    }
}
