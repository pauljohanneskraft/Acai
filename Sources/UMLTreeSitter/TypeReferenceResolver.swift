@preconcurrency import SwiftTreeSitter
import UMLCore

/// Interprets a captured type-expression node (`@member.type`, `@member.param.type`, …) into a
/// `TypeReference`. This is genuinely per-language behavior — Python's `Optional[X]`/PEP-604 unions,
/// Java's generics, Kotlin's nullable suffix, and C++'s templates each need their own recursive
/// interpretation of a type expression — so it is a value a language plugin constructs with its own
/// closure, not something the shared assemblers can derive from a flat capture table.
public struct TypeReferenceResolver: Sendable {
    private let resolve: @Sendable (Node, ParsedSource) -> TypeReference

    public init(_ resolve: @escaping @Sendable (Node, ParsedSource) -> TypeReference) {
        self.resolve = resolve
    }

    public func callAsFunction(_ node: Node, in source: ParsedSource) -> TypeReference {
        resolve(node, source)
    }
}
