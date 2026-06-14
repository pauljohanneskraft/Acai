/// A single problem encountered while parsing a source file. Concrete enough to point a
/// reader at the offending location; the available detail depends on the backend
/// (Tree-sitter gives a location and a generic kind, SwiftSyntax adds a human-readable message).
public struct ParseDiagnostic: Codable, Equatable, Hashable, Sendable {
    /// What kind of parse problem this is.
    public enum Kind: String, Codable, Sendable {
        /// An `ERROR` node: the parser could not make sense of the input here.
        case error
        /// A token the grammar required but the source omitted (inserted during recovery).
        case missing
    }

    public var location: SourceLocation
    public var kind: Kind
    public var message: String

    public init(location: SourceLocation, kind: Kind, message: String) {
        self.location = location
        self.kind = kind
        self.message = message
    }
}
