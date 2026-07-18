import AcaiCore

/// "Only `only`-matching types may depend into `into`." Any edge whose target matches `into` but
/// whose source does *not* match `only` is a violation — e.g. only `@Repository` types may touch
/// the database layer.
public struct StereotypeContract: Codable, Equatable, Sendable {
    /// The protected region edges point *into*.
    public var into: Selector
    /// The only types allowed to depend into that region.
    public var only: Selector
    /// Which edge kinds count; `nil` means all kinds.
    public var kinds: Set<Relationship.Kind>?
    public var message: String?

    public init(into: Selector, only: Selector, kinds: Set<Relationship.Kind>? = nil, message: String? = nil) {
        self.into = into
        self.only = only
        self.kinds = kinds
        self.message = message
    }
}
