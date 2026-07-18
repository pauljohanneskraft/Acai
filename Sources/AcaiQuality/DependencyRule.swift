import AcaiCore

/// "`from` must not depend on `to`." A breach is any relationship whose source matches `from` and
/// target matches `to` (optionally restricted to certain edge `kinds`).
public struct DependencyRule: Codable, Equatable, Sendable {
    public var from: Selector
    public var to: Selector
    /// Which edge kinds count as a dependency for this rule; `nil` means all kinds.
    public var kinds: Set<Relationship.Kind>?
    /// Optional override for the violation message.
    public var message: String?

    public init(from: Selector, to: Selector, kinds: Set<Relationship.Kind>? = nil, message: String? = nil) {
        self.from = from
        self.to = to
        self.kinds = kinds
        self.message = message
    }
}
