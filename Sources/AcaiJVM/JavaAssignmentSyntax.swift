import AcaiCore
import AcaiTreeSitter

struct JavaAssignmentSyntax: AssignmentSyntax {

    let context: SourceFileContext
    private let literals: LiteralClassifier

    /// Names of every `enum_constant` in the file, so an unscoped enum constant assigned to a
    /// variable (`state = READY;`) is recognised as an enumerable value for state-machine analysis
    /// (mirrors the C/C++ extractor's handling).
    private let declaredEnumConstants: Set<String>

    private static let literalNodeTypes = LiteralNodeTypes(
        boolean: ["true", "false"],
        numeric: ["decimal_integer_literal", "hex_integer_literal", "octal_integer_literal",
                  "binary_integer_literal", "decimal_floating_point_literal", "hex_floating_point_literal"],
        string: ["string_literal", "character_literal"],
        nilLiteral: ["null_literal"]
    )

    init(context: SourceFileContext, declaredEnumConstants: Set<String>) {
        self.context = context
        self.declaredEnumConstants = declaredEnumConstants
        literals = LiteralClassifier(context: context, literals: Self.literalNodeTypes)
    }

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
              let target = left.text(in: context).assignmentTarget
        else { return nil }
        let opText = node.child(byFieldName: "operator").map { $0.text(in: context) } ?? "="
        let op: VariableAssignment.Operator = opText == "=" ? .assign : .compound
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
        guard let operand = node.namedChildren().first,
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
        if node.nodeType == "identifier" {
            // An unscoped enum constant (`state = READY;`) is a bare identifier; classify it as an
            // enumerable case when it names a known constant, else an opaque expression. No scope
            // tracking, so a local/field sharing an enum-constant name is also treated as that case —
            // an accepted false positive, rare given the UPPER_CASE-constant vs lowerCamel convention.
            return declaredEnumConstants.contains(valueText)
                ? .init(kind: .enumCase, text: valueText)
                : .init(kind: .expression, text: node.expressionSnippet(in: context))
        }
        if let enumCase = valueText.enumCaseValue {
            return enumCase
        }
        return .init(kind: .expression, text: node.expressionSnippet(in: context))
    }
}
