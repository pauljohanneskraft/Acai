import MCP

/// A thin, typed reader over an MCP tool call's `arguments` object. A value you wrap around the raw
/// `[String: Value]` (`ToolArguments(params.arguments)`) and pull typed facets off — so each tool
/// reads its inputs the same way instead of hand-unwrapping `Value` cases. Missing optional keys
/// return `nil`; a missing *required* key throws `invalidParams` with the offending name.
struct ToolArguments: Sendable {
    private let values: [String: Value]

    init(_ values: [String: Value]?) {
        self.values = values ?? [:]
    }

    func string(_ key: String) -> String? {
        values[key]?.stringValue
    }

    func int(_ key: String) -> Int? {
        values[key]?.intValue
    }

    func bool(_ key: String) -> Bool? {
        values[key]?.boolValue
    }

    func stringArray(_ key: String) -> [String] {
        values[key]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    /// A non-empty string argument, or `invalidParams` naming the key when it is absent or blank.
    func requiredString(_ key: String) throws -> String {
        guard let value = string(key), !value.isEmpty else {
            throw MCPError.invalidParams("Missing required argument '\(key)'.")
        }
        return value
    }
}
