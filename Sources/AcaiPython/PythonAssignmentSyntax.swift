import AcaiCore
import AcaiTreeSitter

/// Python's half of assignment extraction: classify one node as an assignment, and classify a
/// right-hand side as a value.
///
/// The recursion lives in `AcaiTreeSitter`'s ``AssignmentResolver``, which holds one of these; the
/// literal table is handed to a shared ``LiteralClassifier``, built once here rather than per call.
struct PythonAssignmentSyntax: AssignmentSyntax {

    let context: SourceFileContext
    private let literals: LiteralClassifier

    init(context: SourceFileContext) {
        self.context = context
        literals = LiteralClassifier(
            context: context,
            literals: LiteralNodeTypes(
                boolean: ["true", "false"],
                numeric: ["integer", "float"],
                string: ["string", "concatenated_string"],
                nilLiteral: ["none"]
            )
        )
    }

    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment":
            return assignment(node, op: .assign)
        case "augmented_assignment":
            return assignment(node, op: .compound)
        default:
            return nil
        }
    }

    private func assignment(_ node: Node, op: VariableAssignment.Operator) -> VariableAssignment? {
        guard let left = node.child(byFieldName: "left"),
              let target = left.text(in: context).assignmentTarget,
              let right = node.child(byFieldName: "right") else { return nil }
        // Compound results depend on the previous value: record the whole statement as a
        // non-enumerable expression.
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

    /// Also used for a field's or module variable's initial value, which is the same question asked
    /// of a node that is not itself an assignment.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = literals.value(of: node) { return literal }
        if let enumCase = node.trimmedText(in: context).enumCaseValue { return enumCase }
        return .init(kind: .expression, text: node.expressionSnippet(in: context))
    }
}
