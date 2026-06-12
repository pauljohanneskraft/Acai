import UMLCore
import UMLTreeSitter

// MARK: - Assignment Extraction

extension JSExtractor: AssignmentResolving {

    /// Resolves JS/TS `assignment_expression` (`x = …`),
    /// `augmented_assignment_expression` (`x += …`), and
    /// `update_expression` (`x++`, `--x`) nodes.
    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment_expression":
            return resolveAssignmentExpression(node, op: .assign)
        case "augmented_assignment_expression":
            return resolveAssignmentExpression(node, op: .compound)
        case "update_expression":
            return resolveUpdateExpression(node)
        default:
            return nil
        }
    }

    private func resolveAssignmentExpression(
        _ node: Node,
        op: VariableAssignment.Operator
    ) -> VariableAssignment? {
        guard let left = node.child(byFieldName: "left"),
              let right = node.child(byFieldName: "right"),
              let target = parseAssignmentTarget(text(left))
        else { return nil }
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
        guard let operand = node.child(byFieldName: "argument") ?? node.namedChildren().first,
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
        case "number":
            return .init(kind: .numericLiteral, text: valueText)
        case "string", "template_string":
            return .init(kind: .stringLiteral, text: valueText)
        case "null", "undefined":
            return .init(kind: .nilLiteral, text: valueText)
        default:
            if let enumCase = enumCaseValue(fromAccessText: valueText) {
                return enumCase
            }
            return .init(kind: .expression, text: expressionSnippet(node))
        }
    }
}
