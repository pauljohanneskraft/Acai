import MCP

/// A string argument with a closed set of accepted values. The schema's `enum` list and the
/// validation both read `Option.allCases`, so the two cannot drift: an option added to the type
/// reaches the schema and the parser together, and a value in neither is rejected rather than
/// silently dropped.
struct EnumArgument<Option: RawRepresentable & CaseIterable>: Sendable where Option.RawValue == String {
    let name: String
    let description: String

    var accepted: [String] { Option.allCases.map(\.rawValue) }

    /// The argument's entry in a tool's `inputSchema` properties, ready to merge.
    var property: [String: Value] {
        [
            name: [
                "type": "string",
                "enum": .array(accepted.map(Value.string)),
                "description": .string(description)
            ]
        ]
    }

    /// `nil` when the argument is absent; an unrecognised value throws `invalidParams` naming the
    /// argument, the value received and the accepted values.
    func value(in arguments: ToolArguments) throws -> Option? {
        guard let raw = arguments.string(name) else { return nil }
        guard let option = Option(rawValue: raw) else {
            throw MCPError.invalidParams(
                "Argument '\(name)' must be one of: \(accepted.joined(separator: ", ")) (got '\(raw)').")
        }
        return option
    }

    func value(in arguments: ToolArguments, or fallback: Option) throws -> Option {
        try value(in: arguments) ?? fallback
    }
}
