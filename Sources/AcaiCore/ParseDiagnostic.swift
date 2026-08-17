/// A single problem encountered while parsing a source file. The available detail depends on the
/// backend (Tree-sitter gives a location and a generic kind, SwiftSyntax adds a human-readable
/// message).
public struct ParseDiagnostic: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// A Tree-sitter `ERROR` node: the parser could not make sense of the input here.
        case error
        /// A token the grammar required but the source omitted (inserted during recovery).
        case missing
        /// A type reference that matched several declared types by simple name and so was left
        /// unresolved (an ambiguous identity — see ``TypeIdentityResolver``) rather than bound to an
        /// arbitrary one. Not a parse failure: the artifact is usable, but an edge may be missing.
        case unresolvedReference
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
