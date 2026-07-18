import AcaiCore
import AcaiTreeSitter

// MARK: - Assignment extraction

extension CFamilyExtractor: AssignmentResolving {

    /// Resolves C/C++ `assignment_expression` nodes (`x = …`, `x += …`) and `update_expression`
    /// increments/decrements (`x++`, `++x`). Targets a plain identifier or a `this->field` access;
    /// scoped enum values (`State::ready`) are classified as enum cases for state-machine analysis.
    func resolveAssignment(_ node: Node) -> VariableAssignment? {
        switch node.nodeType {
        case "assignment_expression":
            return resolveAssignmentExpression(node)
        case "update_expression":
            return resolveUpdate(node)
        default:
            return nil
        }
    }

    private func resolveAssignmentExpression(_ node: Node) -> VariableAssignment? {
        guard let left = node.child(byFieldName: "left"),
              let target = assignmentTarget(left)
        else { return nil }

        let opText = node.child(byFieldName: "operator").map { text($0) } ?? "="
        let op: VariableAssignment.Operator = opText == "=" ? .assign : .compound
        let value: VariableAssignment.Value
        if op == .compound {
            // Compound results depend on the previous value: record as a non-enumerable expression.
            value = .init(kind: .expression, text: expressionSnippet(node))
        } else if let right = node.child(byFieldName: "right") {
            value = classifyValue(right)
        } else {
            value = .init(kind: .expression, text: expressionSnippet(node))
        }
        return VariableAssignment(
            targetName: target.name, targetReceiver: target.receiver,
            op: op, value: value, location: loc(node)
        )
    }

    private func resolveUpdate(_ node: Node) -> VariableAssignment? {
        guard let argument = node.child(byFieldName: "argument"),
              let target = assignmentTarget(argument)
        else { return nil }
        return VariableAssignment(
            targetName: target.name, targetReceiver: target.receiver,
            op: .compound, value: .init(kind: .expression, text: expressionSnippet(node)),
            location: loc(node)
        )
    }

    /// The assigned target as `(name, receiver)`: a plain identifier (`state`), `this->field` /
    /// `this.field` (receiver dropped), `param->field` where `param` is a typed parameter of the
    /// enclosing free function (the parameter's struct type is kept as receiver), or `Type::field`
    /// (uppercase receiver kept).
    private func assignmentTarget(_ node: Node) -> (name: String, receiver: String?)? {
        switch node.nodeType {
        case "identifier", "field_identifier":
            return (text(node), nil)
        case "field_expression":
            guard let receiver = node.child(byFieldName: "argument"),
                  let field = node.child(byFieldName: "field")
            else { return nil }
            if receiver.nodeType == "this" {
                return (text(field), nil)
            }
            // `param->field` / `param.field` resolves to the parameter's type, so the write feeds
            // that struct's state machine even though it happens in a free function (C has no
            // methods). Only the current free function's typed parameters are in scope.
            if receiver.nodeType == "identifier", let receiverType = currentReceiverTypes[text(receiver)] {
                return (text(field), receiverType)
            }
            return nil
        case "qualified_identifier":
            return parseAssignmentTarget(
                text(node).replacingOccurrences(of: "::", with: "."))
        default:
            return nil
        }
    }

    private static let literalNodeTypes = LiteralNodeTypes(
        boolean: ["true", "false"],
        numeric: ["number_literal"],
        string: ["string_literal", "concatenated_string", "raw_string_literal"],
        nilLiteral: ["null", "nullptr"]
    )

    /// Classifies an assigned value node for static state analysis. Scoped enum accesses
    /// (`State::ready`) and unscoped uppercase enum cases become `.enumCase` values.
    func classifyValue(_ node: Node) -> VariableAssignment.Value {
        if let literal = classifyLiteral(node, Self.literalNodeTypes) { return literal }
        let valueText = trimmedText(node)
        switch node.nodeType {
        case "qualified_identifier":
            return enumCaseValue(fromAccessText: valueText.replacingOccurrences(of: "::", with: "."))
                ?? .init(kind: .expression, text: expressionSnippet(node))
        case "identifier":
            // An unscoped enum constant (C's `state = DOWNLOADING`) is a bare identifier; classify
            // it as an enumerable case when it names a known constant, else an opaque expression.
            return declaredEnumConstants.contains(valueText)
                ? .init(kind: .enumCase, text: valueText)
                : .init(kind: .expression, text: expressionSnippet(node))
        default:
            return .init(kind: .expression, text: expressionSnippet(node))
        }
    }
}
