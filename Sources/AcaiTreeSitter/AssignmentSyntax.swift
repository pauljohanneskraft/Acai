import AcaiCore
import Foundation

// MARK: - AssignmentSyntax

/// One language's answer to "is this node an assignment?".
///
/// Mirrors ``CallSiteSyntax``. Unlike call sites, assignments need no scope tracking — they are
/// recorded for any identifier or `this.<field>` target, and consumers filter by name later.
public protocol AssignmentSyntax {

    var context: SourceFileContext { get }

    func resolveAssignment(_ node: Node) -> VariableAssignment?
}

// MARK: - AssignmentResolver

/// Collects a body's assignments, in source (pre-order) order.
public struct AssignmentResolver {

    private let syntax: any AssignmentSyntax

    public init(syntax: any AssignmentSyntax) {
        self.syntax = syntax
    }

    public func assignments(in body: Node?) -> [VariableAssignment] {
        guard let body else { return [] }
        var assignments: [VariableAssignment] = []
        collect(body, into: &assignments)
        return assignments
    }

    private func collect(_ node: Node, into assignments: inout [VariableAssignment]) {
        if let assignment = syntax.resolveAssignment(node) {
            assignments.append(assignment)
        }
        for child in node.namedChildren() {
            collect(child, into: &assignments)
        }
    }
}

// MARK: - LiteralClassifier

/// Classifies a right-hand side as a literal, against one language's node-type table.
public struct LiteralClassifier: Sendable {

    private let context: SourceFileContext
    private let literals: LiteralNodeTypes

    public init(context: SourceFileContext, literals: LiteralNodeTypes) {
        self.context = context
        self.literals = literals
    }

    /// `nil` when not a recognised literal, letting the caller apply language-specific fallbacks.
    /// The node type is matched before source text is extracted, so the common non-literal path
    /// avoids that cost.
    public func value(of node: Node) -> VariableAssignment.Value? {
        let nodeType = node.nodeType ?? ""
        if literals.boolean.contains(nodeType) {
            return .init(kind: .booleanLiteral, text: node.trimmedText(in: context))
        }
        if literals.numeric.contains(nodeType) {
            return .init(kind: .numericLiteral, text: node.trimmedText(in: context))
        }
        if literals.string.contains(nodeType) {
            let interpolated = !literals.interpolationChildTypes.isEmpty
                && node.namedChildren().contains { literals.interpolationChildTypes.contains($0.nodeType ?? "") }
            return interpolated
                ? .init(kind: .expression, text: node.expressionSnippet(in: context))
                : .init(kind: .stringLiteral, text: node.trimmedText(in: context))
        }
        if literals.nilLiteral.contains(nodeType) {
            return .init(kind: .nilLiteral, text: node.trimmedText(in: context))
        }
        return nil
    }
}

/// The grammar node types a language uses for each literal kind, so ``LiteralClassifier`` stays
/// language-agnostic.
public struct LiteralNodeTypes: Sendable {
    public var boolean: Set<String>
    public var numeric: Set<String>
    public var string: Set<String>
    public var nilLiteral: Set<String>
    /// Child node types that mark a string as interpolated (`"x${y}"`) — runtime-dependent, so it
    /// is classified as an opaque expression rather than a fixed string state.
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

// MARK: - Text shapes

extension Node {

    public func trimmedText(in context: SourceFileContext) -> String {
        text(in: context).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// This node's source on one line, elided past 80 characters — what an unclassifiable
    /// right-hand side is recorded as.
    public func expressionSnippet(in context: SourceFileContext) -> String {
        let raw = text(in: context)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard raw.count > 80 else { return raw }
        return String(raw.prefix(77)) + "..."
    }
}

extension String {

    /// An assignment target parsed into a simple name plus an optional type receiver. Accepts `x`,
    /// `this.x`/`self.x` (receiver stripped), and `Type.x` (receiver kept). Anything else (chained
    /// accesses, subscripts, lowercase instance receivers) is `nil`.
    public var assignmentTarget: (name: String, receiver: String?)? {
        let parts = trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ".")
        guard parts.allSatisfy(\.isPlainIdentifier) else { return nil }
        switch parts.count {
        case 1:
            return (parts[0], nil)
        case 2 where parts[0] == "this" || parts[0] == "self":
            return (parts[1], nil)
        case 2 where parts[0].first?.isUppercase == true:
            return (parts[1], parts[0])
        default:
            return nil
        }
    }

    /// This access expression read as an enum-case value, when it has the shape `Type.caseName`
    /// with an uppercase-initial receiver.
    public var enumCaseValue: VariableAssignment.Value? {
        let parts = trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ".")
        guard parts.count == 2,
              parts.allSatisfy(\.isPlainIdentifier),
              parts[0].first?.isUppercase == true
        else { return nil }
        return VariableAssignment.Value(kind: .enumCase, text: parts[1], receiverTypeName: parts[0])
    }

    /// A bare `foo_1` identifier: no dots, brackets, calls or operators.
    var isPlainIdentifier: Bool {
        guard let first, first.isLetter || first == "_" else { return false }
        return allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
