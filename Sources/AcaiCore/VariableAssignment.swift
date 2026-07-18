/// A statically-observable write to a variable, recorded inside a `Member`'s
/// body during source analysis.
///
/// Parsers populate `Member.assignments` for every assignment whose target is a
/// plain identifier or an explicit `self`/`this` member access. No scope tracking
/// is performed, so a local variable shadowing a property is recorded under the
/// same name — consumers filter by name and tolerate that ambiguity.
public struct VariableAssignment: Codable, Equatable, Hashable, Sendable {

    /// How the variable is written.
    public enum Operator: String, Codable, Equatable, Hashable, Sendable {
        /// A plain assignment (`=`).
        case assign
        /// A compound mutation (`+=`, `-=`, `x++`, `--x`, …) whose result depends
        /// on the previous value and is therefore not statically enumerable.
        case compound
    }

    /// The assigned value, classified for static state analysis.
    public struct Value: Codable, Equatable, Hashable, Sendable {

        public enum Kind: String, Codable, Equatable, Hashable, Sendable {
            /// An enum case reference (`.loading`, `State.LOADING`).
            case enumCase
            case booleanLiteral
            case numericLiteral
            case stringLiteral
            /// `nil` / `null` / `undefined`.
            case nilLiteral
            /// Anything not statically enumerable (calls, parameters, arithmetic, …).
            case expression
        }

        public var kind: Kind

        /// Canonical text: the case name without its receiver (`"loading"`), the
        /// literal's source text (`"true"`, `"42"`, `"\"idle\""`), or a trimmed
        /// snippet for `.expression`.
        public var text: String

        /// The explicit receiver of an `.enumCase` written as `Type.case`, e.g. `"State"`.
        public var receiverTypeName: String?

        public init(kind: Kind, text: String, receiverTypeName: String? = nil) {
            self.kind = kind
            self.text = text
            self.receiverTypeName = receiverTypeName
        }
    }

    /// The assigned variable's simple name (`"state"` for `self.state = …`).
    public var targetName: String

    /// The target's explicit receiver, normalized: `nil` for a bare identifier and
    /// for `self.`/`this.` accesses (parsers strip those); a type name for statics
    /// written as `Type.variable = …`.
    public var targetReceiver: String?

    public var op: Operator

    public var value: Value

    /// Source location of the assignment expression.
    public var location: SourceLocation?

    public init(
        targetName: String,
        targetReceiver: String? = nil,
        op: Operator,
        value: Value,
        location: SourceLocation? = nil
    ) {
        self.targetName = targetName
        self.targetReceiver = targetReceiver
        self.op = op
        self.value = value
        self.location = location
    }
}
