import AcaiCore
import AcaiTreeSitter

// MARK: - Assignment Extraction

extension JavaExtractor: AssignmentResolving {

    /// Resolves Java `assignment_expression` nodes (`x = …`, `x += …`) and
    /// `update_expression` increments (`x++`, `--x`).
    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment_expression":
            return resolveAssignmentExpression(node)
        case "update_expression":
            return resolveUpdateExpression(node)
        default:
            return nil
        }
    }

    private func resolveAssignmentExpression(_ node: Node) -> VariableAssignment? {
        guard let left = node.child(byFieldName: "left"),
              let right = node.child(byFieldName: "right"),
              let target = parseAssignmentTarget(text(left))
        else { return nil }
        let opText = node.child(byFieldName: "operator").map { text($0) } ?? "="
        let op: VariableAssignment.Operator = opText == "=" ? .assign : .compound
        // Compound results depend on the previous value: record the whole
        // statement as a non-enumerable expression.
        let value: VariableAssignment.Value = op == .compound
            ? .init(kind: .expression, text: expressionSnippet(node))
            : classifyValue(right)
        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: op,
            value: value,
            location: loc(node)
        )
    }

    private func resolveUpdateExpression(_ node: Node) -> VariableAssignment? {
        guard let operand = node.namedChildren().first,
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

    private static let literalNodeTypes = LiteralNodeTypes(
        boolean: ["true", "false"],
        numeric: ["decimal_integer_literal", "hex_integer_literal", "octal_integer_literal",
                  "binary_integer_literal", "decimal_floating_point_literal", "hex_floating_point_literal"],
        string: ["string_literal", "character_literal"],
        nilLiteral: ["null_literal"]
    )

    /// Classifies an assigned value node for static state analysis.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = classifyLiteral(node, Self.literalNodeTypes) { return literal }
        let valueText = trimmedText(node)
        if node.nodeType == "identifier" {
            // An unscoped enum constant (`state = READY;`) is a bare identifier; classify it as an
            // enumerable case when it names a known constant, else an opaque expression. This module
            // does not track scopes (see `AssignmentResolving`), so a local/field/parameter that
            // happens to share an enum-constant name is also treated as that case — an accepted
            // false positive, kept rare in practice by the UPPER_CASE-constant vs lowerCamel-variable
            // convention.
            return declaredEnumConstants.contains(valueText)
                ? .init(kind: .enumCase, text: valueText)
                : .init(kind: .expression, text: expressionSnippet(node))
        }
        if let enumCase = enumCaseValue(fromAccessText: valueText) {
            return enumCase
        }
        return .init(kind: .expression, text: expressionSnippet(node))
    }
}
