import UMLCore
import UMLTreeSitter

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

    /// Classifies an assigned value node for static state analysis.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        let valueText = text(node).trimmingCharacters(in: .whitespacesAndNewlines)
        switch node.nodeType {
        case "true", "false":
            return .init(kind: .booleanLiteral, text: valueText)
        case "decimal_integer_literal", "hex_integer_literal", "octal_integer_literal",
             "binary_integer_literal", "decimal_floating_point_literal", "hex_floating_point_literal":
            return .init(kind: .numericLiteral, text: valueText)
        case "string_literal", "character_literal":
            return .init(kind: .stringLiteral, text: valueText)
        case "null_literal":
            return .init(kind: .nilLiteral, text: "null")
        default:
            if let enumCase = enumCaseValue(fromAccessText: valueText) {
                return enumCase
            }
            return .init(kind: .expression, text: expressionSnippet(node))
        }
    }
}
