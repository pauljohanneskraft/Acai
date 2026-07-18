import Foundation

extension StateDiagramConfiguration {
    /// Parses a `--state-from` / `stateFrom` value into a configuration. `"TypeName.variableName"`
    /// selects a property (split on the *last* dot, so nested type names keep their dots); a single
    /// segment selects a global. The behaviour lives on the configuration it produces rather than in a
    /// separate namespace. Shared by the CLI and the MCP; throws `DiagramRequestError` on a malformed
    /// value.
    public init(stateFrom value: String, maxStates: Int) throws {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let invalid = DiagramRequestError(
            "state variable must be \"TypeName.variableName\" or \"variableName\" for a global."
        )
        guard !trimmed.isEmpty else { throw invalid }
        guard let lastDot = trimmed.lastIndex(of: ".") else {
            self.init(typeName: nil, variableName: trimmed, maxStates: maxStates)
            return
        }
        let typeName = String(trimmed[..<lastDot])
        let variableName = String(trimmed[trimmed.index(after: lastDot)...])
        guard !typeName.isEmpty, !variableName.isEmpty else { throw invalid }
        self.init(typeName: typeName, variableName: variableName, maxStates: maxStates)
    }
}
