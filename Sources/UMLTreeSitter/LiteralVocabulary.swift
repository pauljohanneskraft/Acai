/// The grammar node types a language uses for each literal kind, so the shared value-classifier
/// stays language-agnostic. Each set lists the node-type names that map to that literal kind.
public struct LiteralVocabulary: Sendable {
    public var boolean: Set<String>
    public var numeric: Set<String>
    public var string: Set<String>
    public var nilLiteral: Set<String>
    /// Child node types that mark a string as interpolated (`"x${y}"`) — runtime-dependent, so it is
    /// classified as an opaque expression rather than a fixed string state.
    public var interpolationChildTypes: Set<String>

    public init(
        boolean: Set<String> = [],
        numeric: Set<String> = [],
        string: Set<String> = [],
        nilLiteral: Set<String> = [],
        interpolationChildTypes: Set<String> = []
    ) {
        self.boolean = boolean
        self.numeric = numeric
        self.string = string
        self.nilLiteral = nilLiteral
        self.interpolationChildTypes = interpolationChildTypes
    }
}
