import MCP

/// A thin, typed reader over an MCP tool call's `arguments` object. Missing optional keys return
/// `nil`; a missing *required* key throws `invalidParams` naming it.
struct ToolArguments: Sendable {
    private let values: [String: Value]

    init(_ values: [String: Value]?) {
        self.values = values ?? [:]
    }

    func string(_ key: String) -> String? {
        values[key]?.stringValue
    }

    /// A present value that isn't a JSON integer throws `invalidParams` rather than reading as `nil`.
    func int(_ key: String) throws -> Int? {
        try typed(key, as: "an integer", \.intValue)
    }

    /// A whole-valued JSON number decodes as `.int`, so both `.double` and `.int` are accepted.
    func double(_ key: String) throws -> Double? {
        guard let value = values[key] else { return nil }
        if let double = value.doubleValue { return double }
        if let int = value.intValue { return Double(int) }
        throw MCPError.invalidParams("Argument '\(key)' must be a number.")
    }

    /// A present non-boolean (e.g. the string `"true"`) throws `invalidParams` rather than reading as
    /// `nil` — a mistyped `refresh` argument should be rejected, not silently ignored.
    func bool(_ key: String) throws -> Bool? {
        try typed(key, as: "a boolean", \.boolValue)
    }

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

    func requiredString(_ key: String) throws -> String {
        guard let value = string(key), !value.isEmpty else {
            throw MCPError.invalidParams("Missing required argument '\(key)'.")
        }
        return value
    }
}
