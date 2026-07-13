import Foundation
@preconcurrency import SwiftTreeSitter

/// A compiled `.scm` structural query, executed against a `ParsedSource`. Predicate directives
/// (`#eq?`, `#match?`, `#any-of?`, …) are evaluated against the source's own text, so a language's
/// query can classify shapes (e.g. "this identifier's text is `self` or `cls`") declaratively
/// instead of pushing that decision into Swift.
public struct StructuralQuery: Sendable {
    private let query: Query

    /// - Throws: `QueryError` when `source` (the `.scm` text) doesn't compile against `language` —
    ///   a plugin-authoring bug, not a runtime condition.
    public init(language: Language, source: String) throws {
        self.query = try Query(language: language, data: Data(source.utf8))
    }

    /// Every match of this query against `parsedSource`'s root node, with `#eq?`/`#match?`/…
    /// predicates already applied (a match that fails its predicates is excluded).
    public func matches(in parsedSource: ParsedSource) -> [QueryMatch] {
        let cursor = query.execute(in: parsedSource.tree)
        let context = Predicate.Context(string: parsedSource.text)
        return cursor.filter { $0.allowed(in: context) }
    }
}
