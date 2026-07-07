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

    /// The integer at `key`, or `nil` when absent. A present value that isn't a JSON integer throws
    /// `invalidParams` rather than silently reading as `nil` and falling back to a default — a client
    /// sending `"5"` or `5.0` where an integer is expected should be told, not quietly ignored.
    func int(_ key: String) throws -> Int? {
        try typed(key, as: "an integer", \.intValue)
    }

    /// The number at `key`, or `nil` when absent. A whole-valued number decodes as `.int`, so accept
    /// either `.double` or `.int`; any other present type throws `invalidParams`.
    func double(_ key: String) throws -> Double? {
        guard let value = values[key] else { return nil }
        if let double = value.doubleValue { return double }
        if let int = value.intValue { return Double(int) }
        throw MCPError.invalidParams("Argument '\(key)' must be a number.")
    }

    /// The boolean at `key`, or `nil` when absent. A present non-boolean (e.g. the string `"true"`)
    /// throws `invalidParams` instead of silently reading as `nil` — this is what previously let a
    /// mistyped `refresh` quietly serve a stale snapshot.
    func bool(_ key: String) throws -> Bool? {
        try typed(key, as: "a boolean", \.boolValue)
    }

    /// Reads a present value through `project`, throwing `invalidParams` (naming the expected type)
    /// when the key exists but holds the wrong JSON type. Absent keys return `nil`.
    private func typed<T>(_ key: String, as expected: String, _ project: (Value) -> T?) throws -> T? {
        guard let value = values[key] else { return nil }
        guard let projected = project(value) else {
            throw MCPError.invalidParams("Argument '\(key)' must be \(expected).")
        }
        return projected
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
