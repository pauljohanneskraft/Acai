import AcaiCore
import AcaiTreeSitter

struct DartAssignmentSyntax: AssignmentSyntax {

    let context: SourceFileContext
    private let literals: LiteralClassifier

    init(context: SourceFileContext) {
        self.context = context
        // A `string_literal` with a `template_substitution` child (`'$x'`/`'${expr}'`) is
        // runtime-dependent and falls through to an opaque expression.
        literals = LiteralClassifier(
            context: context,
            literals: LiteralNodeTypes(
                numeric: ["decimal_integer_literal", "hex_integer_literal", "decimal_floating_point_literal"],
                string: ["string_literal"],
                nilLiteral: ["null_literal"],
                interpolationChildTypes: ["template_substitution"]
            )
        )
    }

    /// Resolves Dart `assignment_expression` nodes (`x = …`, `x += …`) and increments (`x++` as
    /// `postfix_expression`, `++x` as `unary_expression`, both carrying an `increment_operator`).
    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment_expression":
            return assignmentExpression(node)
        case "postfix_expression", "unary_expression":
            return increment(node)
        default:
            return nil
        }
    }

    private func assignmentExpression(_ node: Node) -> VariableAssignment? {
        guard let left = node.child(byFieldName: "left"),
              let target = left.text(in: context).assignmentTarget
        else { return nil }
        // The grammar flattens the RHS into the assignment node: `LoadState.loading` appears as
        // sibling `identifier` + `selector` children after the operator (`right` covers only the
        // first part). Classify the whole span after the operator instead of a single node.
        let children = node.children()
        guard let opIndex = children.firstIndex(where: {
            !$0.isNamed && $0.text(in: context).hasSuffix("=") && $0.range.location > left.range.location
        }) else { return nil }
        let opText = children[opIndex].text(in: context)
        let op: VariableAssignment.Operator = opText == "=" ? .assign : .compound
        // Compound results depend on the previous value: record as a non-enumerable expression.
        let value: VariableAssignment.Value = op == .compound
            ? .init(kind: .expression, text: node.expressionSnippet(in: context))
            : classifyValueSpan(Array(children[(opIndex + 1)...]))
        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: op,
            value: value,
            location: node.location(in: context)
        )
    }

    private func increment(_ node: Node) -> VariableAssignment? {
        let children = node.children()
        let hasIncrement = children.contains { child in
            child.nodeType == "increment_operator"
                || child.firstChild(withType: "increment_operator") != nil
        }
        guard hasIncrement,
              let operand = children.first(where: { $0.nodeType != "increment_operator" }),
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

    /// `true`/`false` are anonymous tokens in the Dart grammar, so they are
    /// matched by text rather than node type.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = literals.value(of: node) { return literal }
        let valueText = node.trimmedText(in: context)
        if valueText == "true" || valueText == "false" {
            return .init(kind: .booleanLiteral, text: valueText)
        }
        if let enumCase = valueText.enumCaseValue {
            return enumCase
        }
        return .init(kind: .expression, text: node.expressionSnippet(in: context))
    }

    /// Classifies a span of sibling nodes that together form one expression
    /// (the grammar splits accesses like `LoadState.idle` into adjacent parts).
    private func classifyValueSpan(_ parts: [Node]) -> VariableAssignment.Value {
        let parts = parts.filter { $0.isNamed || $0.text(in: context) != ";" }
        if parts.count == 1, let only = parts.first {
            return classifyValue(only)
        }
        let combined = parts.map { $0.text(in: context) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let enumCase = combined.enumCaseValue {
            return enumCase
        }
        let snippet = combined.count > 80 ? String(combined.prefix(77)) + "..." : combined
        return .init(kind: .expression, text: snippet)
    }

    /// Classifies the initializer expression of an `initialized_identifier` or
    /// `static_final_declaration` node (everything after the anonymous `=`).
    func fieldInitializerValue(of node: Node) -> VariableAssignment.Value? {
        let children = node.children()
        guard let eqIndex = children.firstIndex(where: { !$0.isNamed && $0.text(in: context) == "=" }),
              eqIndex + 1 < children.count
        else { return nil }
        return classifyValueSpan(Array(children[(eqIndex + 1)...]))
    }
}
