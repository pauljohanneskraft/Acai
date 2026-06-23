import UMLCore

// MARK: - AssignmentResolving

/// Opt-in protocol for extractors that support assignment extraction.
///
/// Mirrors ``CallSiteResolving``: a language extractor implements
/// ``resolveAssignment(_:)`` for its grammar's assignment node shapes, and the
/// extension provides the recursive walk infrastructure. Unlike call sites,
/// assignments are recorded for *any* identifier or `this.<field>` target —
/// scope tracking is not attempted, so consumers filter by name later.
public protocol AssignmentResolving: TreeSitterExtracting {

    /// Resolves a single AST node to a ``UMLCore/VariableAssignment`` if it
    /// represents an assignment or increment/decrement whose target is a plain
    /// identifier or a `this`-qualified field access.
    ///
    /// Return `nil` for nodes that are not relevant assignment expressions.
    func resolveAssignment(_ node: Node) -> VariableAssignment?
}

/// The grammar node types a language uses for each literal kind, so the shared literal classifier
/// stays language-agnostic. Each set lists the node-type names that map to that literal kind.
public struct LiteralNodeTypes: Sendable {
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

// MARK: - AssignmentResolving Default Implementations

extension AssignmentResolving {

    /// Extracts assignments from a body node, in source (pre-order) order.
    public func extractAssignments(from body: Node?) -> [VariableAssignment] {
        guard let body else { return [] }
        var assignments: [VariableAssignment] = []
        walkForAssignments(body, into: &assignments)
        return assignments
    }

    /// Recursively walks AST nodes, collecting resolved assignments.
    private func walkForAssignments(
        _ node: Node,
        into assignments: inout [VariableAssignment]
    ) {
        if let assignment = resolveAssignment(node) {
            assignments.append(assignment)
        }
        for child in node.namedChildren() {
            walkForAssignments(child, into: &assignments)
        }
    }

    /// Trims an expression's source text to a short snippet suitable for
    /// ``VariableAssignment/Value-swift.struct`` with kind `.expression`.
    public func expressionSnippet(_ node: Node) -> String {
        let raw = text(node)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard raw.count > 80 else { return raw }
        return String(raw.prefix(77)) + "..."
    }

    /// Parses an assignment target's source text into a simple name plus an
    /// optional type receiver.
    ///
    /// Accepts `x`, `this.x`/`self.x` (receiver stripped), and `Type.x`
    /// (uppercase-initial receiver kept). Anything else — chained accesses,
    /// subscripts, lowercase instance receivers — returns `nil` so the
    /// assignment is skipped.
    public func parseAssignmentTarget(_ rawText: String) -> (name: String, receiver: String?)? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: ".")
        guard parts.allSatisfy(Self.isPlainIdentifier) else { return nil }
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

    /// Classifies a node as a literal value using the language's `types`, or returns `nil` when the
    /// node is not a recognised literal — letting the caller apply language-specific fallbacks (bare
    /// enum constants, text-matched keywords, etc.) and the shared `enumCaseValue` tail.
    public func classifyLiteral(_ node: Node, _ types: LiteralNodeTypes) -> VariableAssignment.Value? {
        let valueText = text(node).trimmingCharacters(in: .whitespacesAndNewlines)
        let nodeType = node.nodeType ?? ""
        if types.boolean.contains(nodeType) {
            return .init(kind: .booleanLiteral, text: valueText)
        }
        if types.numeric.contains(nodeType) {
            return .init(kind: .numericLiteral, text: valueText)
        }
        if types.string.contains(nodeType) {
            let interpolated = !types.interpolationChildTypes.isEmpty
                && node.namedChildren().contains { types.interpolationChildTypes.contains($0.nodeType ?? "") }
            return interpolated
                ? .init(kind: .expression, text: expressionSnippet(node))
                : .init(kind: .stringLiteral, text: valueText)
        }
        if types.nilLiteral.contains(nodeType) {
            return .init(kind: .nilLiteral, text: valueText)
        }
        return nil
    }

    /// Classifies an access expression's text as an enum-case value when it has
    /// the shape `Type.caseName` with an uppercase-initial receiver.
    public func enumCaseValue(fromAccessText rawText: String) -> VariableAssignment.Value? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: ".")
        guard parts.count == 2,
              parts.allSatisfy(Self.isPlainIdentifier),
              parts[0].first?.isUppercase == true
        else { return nil }
        return VariableAssignment.Value(kind: .enumCase, text: parts[1], receiverTypeName: parts[0])
    }

    private static func isPlainIdentifier(_ string: String) -> Bool {
        guard let first = string.first, first.isLetter || first == "_" else { return false }
        return string.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
