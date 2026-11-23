import SwiftSyntax

/// Every parameter, closure parameter and pattern binding declared anywhere inside a syntax node.
final class DeclaredNames: SyntaxVisitor {
    private(set) var names: Set<String> = []

    init(in node: some SyntaxProtocol) {
        super.init(viewMode: .sourceAccurate)
        walk(node)
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.identifier.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert((node.secondName ?? node.firstName).text)
        return .visitChildren
    }

    override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert((node.secondName ?? node.firstName).text)
        return .visitChildren
    }

    override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        if node.catchItems.isEmpty { names.insert("error") }
        return .visitChildren
    }
}
