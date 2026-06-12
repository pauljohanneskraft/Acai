import UMLCore

/// Configuration for value-flow state diagram generation: the variable whose
/// statically-observable assignments define the state space.
public struct StateDiagramConfiguration: Codable, Hashable, Sendable {
    /// The name of the type declaring the variable; `nil` for a global/top-level variable.
    public var typeName: String?
    /// The variable's simple name.
    public var variableName: String
    /// The analysis fails with ``StateDiagramAnalysisError/tooManyStates(count:limit:)``
    /// when the variable takes more distinct values than this.
    public var maxStates: Int

    public init(typeName: String? = nil, variableName: String, maxStates: Int = 20) {
        self.typeName = typeName
        self.variableName = variableName
        self.maxStates = maxStates
    }
}

/// Reasons why value-flow state analysis cannot produce a meaningful diagram.
public enum StateDiagramAnalysisError: Error, Equatable, Hashable, Sendable {
    /// No stored property / global variable with the configured name was found.
    case variableNotFound(typeName: String?, variableName: String)
    /// The variable is never assigned an enumerable value anywhere in the codebase
    /// (also reported for artifacts analysed before assignment extraction existed).
    case noAssignments(variableName: String)
    /// An assignment makes the state space non-enumerable (compound mutation
    /// like `+=`/`++`, or a value computed at runtime).
    case unboundedAssignment(memberName: String, reason: String, location: SourceLocation?)
    /// The variable takes more distinct values than the configured limit.
    case tooManyStates(count: Int, limit: Int)
}

extension StateDiagramAnalysisError {
    /// A user-facing description of the failure.
    public var message: String {
        switch self {
        case .variableNotFound(let typeName, let variableName):
            let scope = typeName.map { "type '\($0)'" } ?? "the global scope"
            return "No stored variable named '\(variableName)' was found in \(scope)."
        case .noAssignments(let variableName):
            return "No enumerable assignments to '\(variableName)' were found. "
                + "If this codebase was analysed with an older version, re-analyse it to capture assignments."
        case .unboundedAssignment(let memberName, let reason, _):
            return "The state space is unbounded: \(reason) (in '\(memberName)')."
        case .tooManyStates(let count, let limit):
            return "The variable takes \(count) distinct values, exceeding the limit of \(limit). "
                + "Raise the limit or pick a variable with fewer states."
        }
    }
}
