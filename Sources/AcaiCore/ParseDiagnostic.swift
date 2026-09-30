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
        /// The file itself could not be read (permissions, invalid encoding) — parsing never ran.
        case unreadable
        /// The file was deliberately left out of the analysis — it exceeded the per-file size
        /// ceiling (``AcaiConstants/maximumSourceFileBytes``). The message carries its size, so a
        /// type the user expected to find and cannot is explained rather than simply absent.
        case skipped
        /// A pattern in a file the walker consulted — a `.gitignore` line — could not be read as a
        /// rule. Not a parse failure: the analysis ran, but it excluded less (or more) than the
        /// repository asked for.
        case invalidPattern
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
