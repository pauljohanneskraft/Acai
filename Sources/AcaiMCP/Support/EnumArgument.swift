import MCP

protocol ArgumentOption: RawRepresentable, CaseIterable where RawValue == String {
    /// Keeps deprecated spellings parseable but out of the schema, like ArgumentParser's `allValueStrings`.
    static var advertisedCases: [Self] { get }
}

extension ArgumentOption {
    static var advertisedCases: [Self] { Array(allCases) }
}

struct EnumArgument<Option: ArgumentOption>: Sendable {
    let name: String
    let description: String

    var accepted: [String] { Option.advertisedCases.map(\.rawValue) }

    var property: [String: Value] {
        [
            name: [
                "type": "string",
                "enum": .array(accepted.map(Value.string)),
                "description": .string(description)
            ]
        ]
    }

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
