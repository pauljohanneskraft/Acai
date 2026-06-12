import ArgumentParser
import UMLDiagram

/// Parses the `--state-from` value into a `StateDiagramConfiguration`.
///
/// `"TypeName.variableName"` selects a property (split on the *last* dot, so
/// nested type names keep their dots); a single segment selects a global.
enum StateVariableSpec {
    static func configuration(from value: String, maxStates: Int) throws -> StateDiagramConfiguration {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw ValidationError(
                "--state-from must be \"TypeName.variableName\" or \"variableName\" for a global."
            )
        }
        guard let lastDot = trimmed.lastIndex(of: ".") else {
            return StateDiagramConfiguration(typeName: nil, variableName: trimmed, maxStates: maxStates)
        }
        let typeName = String(trimmed[..<lastDot])
        let variableName = String(trimmed[trimmed.index(after: lastDot)...])
        guard !typeName.isEmpty, !variableName.isEmpty else {
            throw ValidationError(
                "--state-from must be \"TypeName.variableName\" or \"variableName\" for a global."
            )
        }
        return StateDiagramConfiguration(typeName: typeName, variableName: variableName, maxStates: maxStates)
    }
}
