/// A parsed sequence-diagram entry point. A dotted value is a method (`"TypeName.methodName"`); a bare
/// value (no dot) is a top-level function, carried with an empty `typeName` — which
/// `SequenceDiagramBuilder` resolves against `freestandingFunctions`. A value you construct from the
/// raw string (`SequenceEntryPoint(parsing:)`); shared by the CLI's `--sequence-from` and the MCP.
public struct SequenceEntryPoint: Equatable, Sendable {
    public let typeName: String
    public let methodName: String

    public init(parsing value: String) throws {
        let invalid = DiagramRequestError(
            "sequence entry point must be \"TypeName.methodName\", or a top-level function name."
        )
        guard let dot = value.lastIndex(of: ".") else {
            guard !value.isEmpty else { throw invalid }
            self.typeName = ""
            self.methodName = value
            return
        }
        let typeName = String(value[..<dot])
        let methodName = String(value[value.index(after: dot)...])
        guard !typeName.isEmpty, !methodName.isEmpty else { throw invalid }
        self.typeName = typeName
        self.methodName = methodName
    }

    /// The `(typeName, methodName)` pair `SequenceDiagramBuilder` expects.
    public var components: (typeName: String, methodName: String) {
        (typeName, methodName)
    }
}
