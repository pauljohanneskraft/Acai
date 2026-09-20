import AcaiCore

/// Source-compatibility shim for the language extractors that have not yet been migrated off the
/// monolithic ``TreeSitterExtracting`` shape. See ``CallSiteResolving`` for why it exists and when
/// it goes away.
public protocol AssignmentResolving: TreeSitterExtracting, AssignmentSyntax {}

extension AssignmentResolving {

    /// Extracts assignments from a body node, in source (pre-order) order.
    public func extractAssignments(from body: Node?) -> [VariableAssignment] {
        AssignmentResolver(syntax: self).assignments(in: body)
    }

    public func classifyLiteral(_ node: Node, _ types: LiteralNodeTypes) -> VariableAssignment.Value? {
        LiteralClassifier(context: context, literals: types).value(of: node)
    }

    public func expressionSnippet(_ node: Node) -> String {
        node.expressionSnippet(in: context)
    }

    public func trimmedText(_ node: Node) -> String {
        node.trimmedText(in: context)
    }

    public func parseAssignmentTarget(_ rawText: String) -> (name: String, receiver: String?)? {
        rawText.assignmentTarget
    }

    public func enumCaseValue(fromAccessText rawText: String) -> VariableAssignment.Value? {
        rawText.enumCaseValue
    }
}
