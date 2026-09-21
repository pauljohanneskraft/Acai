import AcaiCore
import AcaiTreeSitter

struct JSAssignmentSyntax: AssignmentSyntax {

    let context: SourceFileContext
    private let literals: LiteralClassifier

    /// JS literal node types. A `template_string` with a `template_substitution` child (`x${y}`) is
    /// runtime-dependent and falls through to an opaque expression.
    private static let literalNodeTypes = LiteralNodeTypes(
        boolean: ["true", "false"],
        numeric: ["number"],
        string: ["string", "template_string"],
        nilLiteral: ["null", "undefined"],
        interpolationChildTypes: ["template_substitution"]
    )

    init(context: SourceFileContext) {
        self.context = context
        literals = LiteralClassifier(context: context, literals: Self.literalNodeTypes)
    }

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
              let target = left.text(in: context).assignmentTarget
        else { return nil }
        // Compound results depend on the previous value: record the whole
        // statement as a non-enumerable expression.
        let value: VariableAssignment.Value = op == .compound
            ? .init(kind: .expression, text: node.expressionSnippet(in: context))
            : classifyValue(right)
        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: op,
            value: value,
            location: node.location(in: context)
        )
    }

    private func resolveUpdateExpression(_ node: Node) -> VariableAssignment? {
        guard let operand = node.child(byFieldName: "argument") ?? node.namedChildren().first,
              let target = operand.text(in: context).assignmentTarget
        else { return nil }
        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: .compound,
            value: .init(kind: .expression, text: node.expressionSnippet(in: context)),
            location: node.location(in: context)
        )
    }

    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = literals.value(of: node) { return literal }
        let valueText = node.trimmedText(in: context)
        if let enumCase = valueText.enumCaseValue {
            return enumCase
        }
        return .init(kind: .expression, text: node.expressionSnippet(in: context))
    }
}
