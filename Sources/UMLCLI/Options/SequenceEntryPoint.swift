import ArgumentParser

/// Parses a `--sequence-from` value into a sequence-diagram entry point.
///
/// A dotted value is a method: `"TypeName.methodName"`. A bare value (no dot) is a top-level
/// function, returned with an empty type name — which `CodeArtifact.sequenceDiagram(entryPoint:)`
/// resolves against `freestandingFunctions`.
func parseSequenceEntryPoint(_ value: String) throws -> (typeName: String, methodName: String) {
    let invalid = ValidationError(
        "--sequence-from must be \"TypeName.methodName\", or a top-level function name."
    )
    guard let dot = value.lastIndex(of: ".") else {
        guard !value.isEmpty else { throw invalid }
        return ("", value)
    }
    let typeName = String(value[..<dot])
    let methodName = String(value[value.index(after: dot)...])
    guard !typeName.isEmpty, !methodName.isEmpty else { throw invalid }
    return (typeName, methodName)
}
