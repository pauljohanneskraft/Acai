import SwiftSyntax

/// Collects bare, type-like (capitalised) names referenced inside a syntax subtree — constructor calls
/// (`Foo(...)`), static/enum access (`Foo.bar`, `Foo.self`), casts and type annotations. Used to
/// surface construction/body dependencies for the coupling metrics; over-capture is harmless because
/// the engine keeps only names that resolve to known types.
final class TypeReferenceCollector: SyntaxVisitor {
    private(set) var names: Set<String> = []

    init() { super.init(viewMode: .sourceAccurate) }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            record(base.baseName.text)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            record(callee.baseName.text)
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text)
        return .visitChildren
    }

    private func record(_ name: String) {
        guard let first = name.first, first.isUppercase else { return }
        names.insert(name)
    }
}
