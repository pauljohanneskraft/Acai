import SwiftSyntax

/// The cyclomatic complexity of a Swift function/initializer body: `1 +` its structural decision points
/// (`if`/`guard`, `for`/`while`/`repeat` loops, `switch` `case`s, `catch` clauses). Each decision counts
/// once at any nesting depth (flat McCabe complexity, not weighted Cognitive Complexity).
/// Expression-level branches (ternary, `&&`/`||`) are excluded to stay consistent with the tree-sitter
/// parsers. `nil` when there's no body, so an aggregate can tell "not measured" from "no branches".
struct SwiftCyclomaticComplexity {
    let body: CodeBlockSyntax?

    var value: Int? {
        guard let body else { return nil }
        let counter = DecisionPointCounter(viewMode: .sourceAccurate)
        counter.walk(body)
        return 1 + counter.decisions
    }

    /// Walks a body counting decision-point syntax nodes. A private implementation detail of the value
    /// above (SwiftSyntax's `SyntaxVisitor` is a class).
    private final class DecisionPointCounter: SyntaxVisitor {
        var decisions = 0

        override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind { count() }
        override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { count() }
        override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind { count() }
        override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { count() }
        override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind { count() }
        override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind { count() }

        override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
            // Count real `case` labels; the `default` is the "else" and doesn't add a branch.
            if case .case = node.label { decisions += 1 }
            return .visitChildren
        }

        private func count() -> SyntaxVisitorContinueKind {
            decisions += 1
            return .visitChildren
        }
    }
}
