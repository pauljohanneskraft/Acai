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

    private static let literalNodeTypes = LiteralNodeTypes(
        boolean: ["true", "false"],
        numeric: ["integer", "float"],
        string: ["string", "concatenated_string"],
        nilLiteral: ["none"]
    )

    /// Classifies an assigned value node for static state analysis.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = classifyLiteral(node, Self.literalNodeTypes) { return literal }
        let valueText = text(node).trimmingCharacters(in: .whitespacesAndNewlines)
        if let enumCase = enumCaseValue(fromAccessText: valueText) {
            return enumCase
        }
        return .init(kind: .expression, text: expressionSnippet(node))
    }
}
