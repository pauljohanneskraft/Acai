import UMLCore
import UMLTreeSitter

// MARK: - Assignment extraction

extension PythonExtractor: AssignmentResolving {

    /// Resolves Python `assignment` (`x = …`, `self.x = …`) and `augmented_assignment` (`x += …`)
    /// nodes whose target is a plain identifier or a `self`-qualified attribute.
    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment":
            return resolveAssignment(node, op: .assign)
        case "augmented_assignment":
            return resolveAssignment(node, op: .compound)
        default:
            return nil
        }
    }

    private func resolveAssignment(_ node: Node, op: VariableAssignment.Operator) -> VariableAssignment? {
        guard let left = node.child(byFieldName: "left"),
              let target = parseAssignmentTarget(text(left)),
              let right = node.child(byFieldName: "right") else { return nil }
        // Compound results depend on the previous value: record the whole statement as a
        // non-enumerable expression.
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

    /// Classifies an assigned value node for static state analysis.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        let valueText = text(node).trimmingCharacters(in: .whitespacesAndNewlines)
        switch node.nodeType {
        case "true", "false":
            return .init(kind: .booleanLiteral, text: valueText)
        case "integer", "float":
            return .init(kind: .numericLiteral, text: valueText)
        case "string", "concatenated_string":
            return .init(kind: .stringLiteral, text: valueText)
        case "none":
            return .init(kind: .nilLiteral, text: valueText)
        default:
            if let enumCase = enumCaseValue(fromAccessText: valueText) {
                return enumCase
            }
            return .init(kind: .expression, text: expressionSnippet(node))
        }
    }
}
