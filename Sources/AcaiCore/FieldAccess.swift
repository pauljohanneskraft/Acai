/// A statically-observable read of a stored property, recorded inside a `Member`'s
/// body during source analysis.
///
/// Mirrors ``VariableAssignment``'s target shape: `receiver` is `nil` for a bare identifier or a
/// `self`/`this` member access (parsers strip those), and a type name for a `Type.field` static
/// read. No scope tracking is performed, so a local variable shadowing a property is recorded under
/// the same name — consumers filter by name and tolerate that ambiguity.
public struct FieldAccess: Codable, Equatable, Hashable, Sendable {

    /// The read property's simple name (`"state"` for `self.state`).
    public var name: String

    /// The access's explicit receiver, normalized: `nil` for a bare identifier and for
    /// `self.`/`this.` accesses (parsers strip those); a type name for statics read as `Type.field`.
    public var receiver: String?

    /// Source location of the read expression.
    public var location: SourceLocation?

    public init(name: String, receiver: String? = nil, location: SourceLocation? = nil) {
        self.name = name
        self.receiver = receiver
        self.location = location
    }
}
