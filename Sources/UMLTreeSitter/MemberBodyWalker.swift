import Foundation
@preconcurrency import SwiftTreeSitter
import UMLCore

/// The result of walking one member's body.
struct BodyAnalysisResult: Sendable {
    var callSites: [CallSite] = []
    var assignments: [VariableAssignment] = []
    var fieldReads: [FieldAccess] = []
    var referencedTypeNames: [String] = []
}

/// Recursive walk of one member's body. Peels `a.b.c()` into (head, hops, methodName) using only
/// `TreeSitterExpressionGrammar` — no grammar-specific strings — and asks `CallReceiverClassifier`
/// to decide each `CallSite.receiver`. Emits `[VariableAssignment]`, `[FieldAccess]`, and
/// `referencedTypeNames` from the same single traversal.
struct MemberBodyWalker: Sendable {
    private let grammar: any TreeSitterExpressionGrammar
    private let receiverClassifier = CallReceiverClassifier()
    private let valueClassifier: LiteralValueClassifier

    init(grammar: any TreeSitterExpressionGrammar, literals: LiteralVocabulary) {
        self.grammar = grammar
        self.valueClassifier = LiteralValueClassifier(grammar: grammar, literals: literals)
    }

    func walk(body: Node, source: ParsedSource, index: KnownMemberIndex) -> BodyAnalysisResult {
        var result = BodyAnalysisResult()
        walk(body, source: source, index: index, into: &result)
        return result
    }

    private func walk(_ node: Node, source: ParsedSource, index: KnownMemberIndex, into result: inout BodyAnalysisResult) {
        if let call = callSite(for: node, source: source, index: index) {
            result.callSites.append(call)
        }
        if let assignment = assignment(for: node, source: source, index: index) {
            result.assignments.append(assignment)
        }
        if grammar.isConstruction(node, in: source), let callee = grammar.callParts(of: node)?.callee,
           let name = grammar.identifierText(of: callee, in: source) {
            result.referencedTypeNames.append(name)
        }
        if let name = grammar.identifierText(of: node, in: source), index.knownPropertyNames.contains(name) {
            result.fieldReads.append(FieldAccess(name: name, receiver: nil, location: node.location(in: source)))
        }
        for child in node.namedChildren() {
            walk(child, source: source, index: index, into: &result)
        }
    }

    // MARK: - Calls

    private func callSite(for node: Node, source: ParsedSource, index: KnownMemberIndex) -> CallSite? {
        guard let (callee, _) = grammar.callParts(of: node) else { return nil }
        let location = node.location(in: source)

        if let (object, methodName) = grammar.memberAccessParts(of: callee, in: source) {
            guard let chain = peelChain(object, source: source), let receiver = receiverClassifier.classify(
                head: chain.head, hops: chain.hops, index: index)
            else { return nil }
            return CallSite(receiver: receiver, methodName: methodName, location: location)
        }

        guard let methodName = grammar.identifierText(of: callee, in: source),
              let receiver = receiverClassifier.classifyBareCall(
                named: methodName, implicitSelf: grammar.bareCallIsImplicitSelf, index: index)
        else { return nil }
        return CallSite(receiver: receiver, methodName: methodName, location: location)
    }

    /// Peels a receiver expression down to its innermost head plus the member names accessed after
    /// it, in order — `self.a.b` → `(.selfKeyword, ["a", "b"])`. `nil` when the chain bottoms out in
    /// something that isn't `self` or a bare identifier (an unresolvable receiver).
    private func peelChain(_ node: Node, source: ParsedSource) -> (head: ReceiverHeadKind, hops: [String])? {
        if grammar.isSelfReference(node, in: source) { return (.selfKeyword, []) }
        if let (object, name) = grammar.memberAccessParts(of: node, in: source) {
            guard let inner = peelChain(object, source: source) else { return nil }
            return (inner.head, inner.hops + [name])
        }
        if let name = grammar.identifierText(of: node, in: source) { return (.identifier(name), []) }
        return nil
    }

    // MARK: - Assignments

    private func assignment(for node: Node, source: ParsedSource, index: KnownMemberIndex) -> VariableAssignment? {
        guard let (target, op, value) = grammar.assignmentParts(of: node) else { return nil }
        guard let (name, receiver) = assignmentTarget(target, source: source, index: index) else { return nil }
        let assignedValue: VariableAssignment.Value = op == .compound
            ? .init(kind: .expression, text: expressionSnippet(node, source: source))
            : valueClassifier.classify(value, in: source)
        return VariableAssignment(
            targetName: name, targetReceiver: receiver, op: op, value: assignedValue,
            location: node.location(in: source))
    }

    /// Resolves an assignment target's receiver: `self.x`/bare `x` → no receiver; `Type.x` (a
    /// capitalized object) → that type name; a lowercase object with a *known* declared type (a
    /// typed property or parameter — this is what makes C's `param->field` state-machine idiom
    /// resolve, with no special-casing beyond `index` already carrying the parameter's type) → that
    /// type. Anything else (an unrelated lowercase receiver) drops the assignment, unchanged from
    /// today's behavior.
    private func assignmentTarget(
        _ node: Node, source: ParsedSource, index: KnownMemberIndex
    ) -> (name: String, receiver: String?)? {
        if let (object, name) = grammar.memberAccessParts(of: node, in: source) {
            if grammar.isSelfReference(object, in: source) { return (name, nil) }
            guard let objectName = grammar.identifierText(of: object, in: source) else { return nil }
            if objectName.first?.isUppercase == true { return (name, objectName) }
            if let knownType = index.knownProperties[objectName] { return (name, knownType) }
            return nil
        }
        guard let name = grammar.identifierText(of: node, in: source) else { return nil }
        return (name, nil)
    }

    private func expressionSnippet(_ node: Node, source: ParsedSource) -> String {
        let raw = node.text(in: source).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard raw.count > 80 else { return raw }
        return String(raw.prefix(77)) + "..."
    }
}
