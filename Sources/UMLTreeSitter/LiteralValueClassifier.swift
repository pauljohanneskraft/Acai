import Foundation
@preconcurrency import SwiftTreeSitter
import UMLCore

/// Classifies an expression node for static state analysis: a literal (per a `LiteralVocabulary`),
/// an enum-case access (`Type.case`, a capitalized-object member access), or an opaque expression.
/// Shared by `MemberBodyWalker` (an assigned value inside a body) and `MemberSignatureAssembler` (a
/// property's declaration-site initializer), so the two never classify the same shape differently.
struct LiteralValueClassifier: Sendable {
    private let grammar: any TreeSitterExpressionGrammar
    private let literals: LiteralVocabulary

    init(grammar: any TreeSitterExpressionGrammar, literals: LiteralVocabulary) {
        self.grammar = grammar
        self.literals = literals
    }

    func classify(_ node: Node, in source: ParsedSource) -> VariableAssignment.Value {
        let nodeType = node.nodeType ?? ""
        if literals.boolean.contains(nodeType) {
            return .init(kind: .booleanLiteral, text: trimmedText(node, source: source))
        }
        if literals.numeric.contains(nodeType) {
            return .init(kind: .numericLiteral, text: trimmedText(node, source: source))
        }
        if literals.string.contains(nodeType) {
            let interpolated = !literals.interpolationChildTypes.isEmpty
                && node.namedChildren().contains { literals.interpolationChildTypes.contains($0.nodeType ?? "") }
            return interpolated
                ? .init(kind: .expression, text: expressionSnippet(node, source: source))
                : .init(kind: .stringLiteral, text: trimmedText(node, source: source))
        }
        if literals.nilLiteral.contains(nodeType) {
            return .init(kind: .nilLiteral, text: trimmedText(node, source: source))
        }
        if let (object, caseName) = grammar.memberAccessParts(of: node, in: source),
           let objectName = grammar.identifierText(of: object, in: source), objectName.first?.isUppercase == true {
            return .init(kind: .enumCase, text: caseName, receiverTypeName: objectName)
        }
        return .init(kind: .expression, text: expressionSnippet(node, source: source))
    }

    private func trimmedText(_ node: Node, source: ParsedSource) -> String {
        node.text(in: source).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func expressionSnippet(_ node: Node, source: ParsedSource) -> String {
        let raw = trimmedText(node, source: source).replacingOccurrences(of: "\n", with: " ")
        guard raw.count > 80 else { return raw }
        return String(raw.prefix(77)) + "..."
    }
}
