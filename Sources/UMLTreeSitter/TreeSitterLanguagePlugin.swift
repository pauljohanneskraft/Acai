@preconcurrency import SwiftTreeSitter
import UMLCore

/// Pure data: everything one language plugin owns. No methods — a language's `CodeParser.init()`
/// builds exactly one of these, once (the compiled `Language`/`Query` are expensive to construct),
/// and every `parse` call reuses it via `TreeSitterSourceFileExtractor`.
public struct TreeSitterLanguagePlugin: Sendable {
    let sourceLanguage: CodeArtifact.SourceLanguage
    let grammar: Language
    let structuralQuery: StructuralQuery
    let vocabulary: TypeStructureVocabulary
    let typeReference: TypeReferenceResolver
    let literals: LiteralVocabulary
    let expressionGrammar: any TreeSitterExpressionGrammar
    /// Identifies a root-level child node as a bare, otherwise-unreachable executable statement (a
    /// top-level call, or Python's `if __name__ == "__main__":` block) whose calls should be
    /// collected into a synthetic `<top-level>` freestanding member (RC-H), so dead-code analysis
    /// doesn't flag their targets as unreachable. `nil` for a language with no top-level executable
    /// statements (most of them — only Python and JS/TS need this).
    let topLevelCallNodePredicate: (@Sendable (Node) -> Bool)?

    public init(
        sourceLanguage: CodeArtifact.SourceLanguage,
        grammar: Language,
        structuralQuery: StructuralQuery,
        vocabulary: TypeStructureVocabulary,
        typeReference: TypeReferenceResolver,
        literals: LiteralVocabulary,
        expressionGrammar: any TreeSitterExpressionGrammar,
        topLevelCallNodePredicate: (@Sendable (Node) -> Bool)? = nil
    ) {
        self.sourceLanguage = sourceLanguage
        self.grammar = grammar
        self.structuralQuery = structuralQuery
        self.vocabulary = vocabulary
        self.typeReference = typeReference
        self.literals = literals
        self.expressionGrammar = expressionGrammar
        self.topLevelCallNodePredicate = topLevelCallNodePredicate
    }
}
