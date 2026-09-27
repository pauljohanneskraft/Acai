/// What a diagram's find bar reports for the query typed into it, and whether stepping between
/// matches is possible.
public struct DiagramSearchSummary: Hashable, Sendable {
    /// One count, not a "one match"/"many matches" split: pluralization belongs to the catalog's
    /// plural variations, not to this rule.
    public enum Message: Hashable, Sendable {
        case noMatches
        case matches(Int)
    }

    /// `nil` before the first keystroke — nothing has been searched for yet, which reads
    /// differently from a query that matched nothing.
    public let message: Message?
    public let canStep: Bool

    public init(query: String, matchCount: Int) {
        if query.isEmpty {
            message = nil
        } else {
            message = matchCount > 0 ? .matches(matchCount) : .noMatches
        }
        canStep = matchCount > 0
    }
}
