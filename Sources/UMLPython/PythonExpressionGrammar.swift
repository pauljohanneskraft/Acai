import UMLCore
import UMLTreeSitter

/// The narrow per-language body-analysis adapter for Python's grammar (field-based: `call { function,
/// arguments }`, `attribute { object, attribute }`, `assignment { left, right }`). Python has no
/// dedicated `self` keyword node — it's a bare `identifier` whose text is `self`/`cls` by convention
/// — so `isSelfReference` checks text, not node type.
struct PythonExpressionGrammar: TreeSitterExpressionGrammar {
    let bareCallIsImplicitSelf = true

    func callParts(of node: Node) -> (callee: Node, arguments: [Node])? {
        guard node.nodeType == "call", let callee = node.child(byFieldName: "function") else { return nil }
        let arguments = node.child(byFieldName: "arguments")?.namedChildren() ?? []
        return (callee, arguments)
    }

    func memberAccessParts(of node: Node, in source: ParsedSource) -> (object: Node, memberName: String)? {
        guard node.nodeType == "attribute",
              let object = node.child(byFieldName: "object"),
              let attribute = node.child(byFieldName: "attribute")
        else { return nil }
        return (object, attribute.text(in: source))
    }

    func assignmentParts(of node: Node) -> (target: Node, op: VariableAssignment.Operator, value: Node)? {
        switch node.nodeType {
        case "assignment":
            guard let target = node.child(byFieldName: "left"), let value = node.child(byFieldName: "right")
            else { return nil }
            return (target, .assign, value)
        case "augmented_assignment":
            guard let target = node.child(byFieldName: "left"), let value = node.child(byFieldName: "right")
            else { return nil }
            return (target, .compound, value)
        default:
            return nil
        }
    }

    func isSelfReference(_ node: Node, in source: ParsedSource) -> Bool {
        guard node.nodeType == "identifier" else { return false }
        let text = node.text(in: source)
        return text == "self" || text == "cls"
    }

    func isConstruction(_ node: Node, in source: ParsedSource) -> Bool {
        guard let (callee, _) = callParts(of: node), callee.nodeType == "identifier" else { return false }
        return callee.text(in: source).first?.isUppercase == true
    }

    func isDecisionPoint(_ node: Node) -> Bool {
        Self.decisionNodeTypes.contains(node.nodeType ?? "")
    }

    func identifierText(of node: Node, in source: ParsedSource) -> String? {
        node.nodeType == "identifier" ? node.text(in: source) : nil
    }

    private static let decisionNodeTypes: Set<String> = [
        "if_statement", "elif_clause", "for_statement", "while_statement", "except_clause", "case_clause"
    ]
}
