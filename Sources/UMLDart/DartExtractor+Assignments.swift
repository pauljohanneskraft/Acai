import UMLCore
import UMLTreeSitter

// MARK: - Assignment Extraction

extension DartExtractor: AssignmentResolving {

    /// Resolves Dart `assignment_expression` nodes (`x = …`, `x += …`) and
    /// increments (`x++` as `postfix_expression`, `++x` as `unary_expression`,
    /// both carrying an `increment_operator`).
    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment_expression":
            return resolveAssignmentExpression(node)
        case "postfix_expression", "unary_expression":
            return resolveIncrement(node)
        default:
            return nil
        }
    }

    private func resolveAssignmentExpression(_ node: Node) -> VariableAssignment? {
        guard let left = node.child(byFieldName: "left"),
              let target = parseAssignmentTarget(text(left))
        else { return nil }
        // The grammar flattens the RHS into the assignment node: `LoadState.loading`
        // appears as sibling `identifier` + `selector` children after the operator
        // token (the `right` field covers only the first part). Classify the span
        // of all children following the operator instead of a single node.
        let children = node.children()
        guard let opIndex = children.firstIndex(where: {
            !$0.isNamed && text($0).hasSuffix("=") && $0.range.location > left.range.location
        }) else { return nil }
        let opText = text(children[opIndex])
        let op: VariableAssignment.Operator = opText == "=" ? .assign : .compound
        // Compound results depend on the previous value: record the whole
        // statement as a non-enumerable expression.
        let value: VariableAssignment.Value = op == .compound
            ? .init(kind: .expression, text: expressionSnippet(node))
            : classifyValueSpan(Array(children[(opIndex + 1)...]))
        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: op,
            value: value,
            location: loc(node)
        )
    }

    private func resolveIncrement(_ node: Node) -> VariableAssignment? {
        let children = node.children()
        let hasIncrement = children.contains { child in
            child.nodeType == "increment_operator"
                || child.firstChild(withType: "increment_operator") != nil
        }
        guard hasIncrement,
              let operand = children.first(where: { $0.nodeType != "increment_operator" }),
              let target = parseAssignmentTarget(text(operand))
        else { return nil }
        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: .compound,
            value: .init(kind: .expression, text: expressionSnippet(node)),
            location: loc(node)
        )
    }

    /// Dart literal node types. A `string_literal` with a `template_substitution` child (`'$x'`/
    /// `'${expr}'`) is runtime-dependent and falls through to an opaque expression.
    private static let literalNodeTypes = LiteralNodeTypes(
        numeric: ["decimal_integer_literal", "hex_integer_literal", "decimal_floating_point_literal"],
        string: ["string_literal"],
        nilLiteral: ["null_literal"],
        interpolationChildTypes: ["template_substitution"]
    )

    /// Classifies an assigned value node for static state analysis.
    /// `true`/`false` are anonymous tokens in the Dart grammar, so they are
    /// matched by text rather than node type.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = classifyLiteral(node, Self.literalNodeTypes) { return literal }
        let valueText = trimmedText(node)
        if valueText == "true" || valueText == "false" {
            return .init(kind: .booleanLiteral, text: valueText)
        }
        if let enumCase = enumCaseValue(fromAccessText: valueText) {
            return enumCase
        }
        return .init(kind: .expression, text: expressionSnippet(node))
    }

    /// Classifies a span of sibling nodes that together form one expression
    /// (the grammar splits accesses like `LoadState.idle` into adjacent parts).
    private func classifyValueSpan(_ parts: [Node]) -> VariableAssignment.Value {
        let parts = parts.filter { $0.isNamed || text($0) != ";" }
        if parts.count == 1, let only = parts.first {
            return classifyValue(only)
        }
        let combined = parts.map { text($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let enumCase = enumCaseValue(fromAccessText: combined) {
            return enumCase
        }
        let snippet = combined.count > 80 ? String(combined.prefix(77)) + "..." : combined
        return .init(kind: .expression, text: snippet)
    }

    /// Classifies the initializer expression of an `initialized_identifier` or
    /// `static_final_declaration` node (everything after the anonymous `=`).
    func fieldInitializerValue(of node: Node) -> VariableAssignment.Value? {
        let children = node.children()
        guard let eqIndex = children.firstIndex(where: { !$0.isNamed && text($0) == "=" }),
              eqIndex + 1 < children.count
        else { return nil }
        return classifyValueSpan(Array(children[(eqIndex + 1)...]))
    }
}
