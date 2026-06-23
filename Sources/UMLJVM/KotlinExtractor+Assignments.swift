import UMLCore
import UMLTreeSitter

// MARK: - Assignment Extraction

extension KotlinExtractor: AssignmentResolving {

    /// Resolves Kotlin `assignment` nodes (`x = …`, `x += …`) and
    /// `prefix_expression`/`postfix_expression` increments (`++x`, `x--`).
    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment":
            return resolvePlainAssignment(node)
        case "prefix_expression", "postfix_expression":
            return resolveIncrement(node)
        default:
            return nil
        }
    }

    /// `assignment` has no fields; its children are positional:
    /// `directly_assignable_expression`, an anonymous operator token, RHS.
    private func resolvePlainAssignment(_ node: Node) -> VariableAssignment? {
        let children = node.children()
        guard children.count >= 3,
              children[0].nodeType == "directly_assignable_expression",
              let target = parseAssignmentTarget(text(children[0]))
        else { return nil }
        let opText = text(children[1]).trimmingCharacters(in: .whitespaces)
        let op: VariableAssignment.Operator = opText == "=" ? .assign : .compound
        // Compound results depend on the previous value: record the whole
        // statement as a non-enumerable expression.
        let value: VariableAssignment.Value = op == .compound
            ? .init(kind: .expression, text: expressionSnippet(node))
            : classifyValue(children[2])
        return VariableAssignment(
            targetName: target.name,
            targetReceiver: target.receiver,
            op: op,
            value: value,
            location: loc(node)
        )
    }

    /// `++`/`--` appear as anonymous operator tokens inside prefix/postfix
    /// expressions; the operand is the remaining child.
    private func resolveIncrement(_ node: Node) -> VariableAssignment? {
        let children = node.children()
        guard children.contains(where: { !$0.isNamed && ["++", "--"].contains(text($0)) }),
              let operand = children.first(where: \.isNamed),
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

    /// Kotlin literal node types. A `string_literal` with an interpolated child (`"$x"`/`"${expr}"`)
    /// is runtime-dependent and falls through to an opaque expression; `character_literal` has no
    /// such children, so it classifies as a plain string.
    private static let literalNodeTypes = LiteralNodeTypes(
        boolean: ["boolean_literal"],
        numeric: ["integer_literal", "hex_literal", "bin_literal",
                  "long_literal", "unsigned_literal", "real_literal"],
        string: ["character_literal", "string_literal"],
        interpolationChildTypes: ["interpolated_expression", "interpolated_identifier"]
    )

    /// Classifies an assigned value node for static state analysis.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = classifyLiteral(node, Self.literalNodeTypes) { return literal }
        let valueText = text(node).trimmingCharacters(in: .whitespacesAndNewlines)
        // Kotlin's `null` is a keyword node rather than a typed literal.
        if valueText == "null" {
            return .init(kind: .nilLiteral, text: "null")
        }
        if let enumCase = enumCaseValue(fromAccessText: valueText) {
            return enumCase
        }
        return .init(kind: .expression, text: expressionSnippet(node))
    }
}
