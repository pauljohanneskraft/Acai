@preconcurrency import SwiftTreeSitter

/// A method body's cyclomatic complexity: `1 +` the count of decision-point nodes (per the
/// language's `TreeSitterExpressionGrammar.isDecisionPoint(_:)`). Kept separate from
/// `MemberBodyWalker` — one counts decision points, the other classifies calls/assignments — so
/// neither type grows past a handful of methods.
struct CyclomaticComplexityCounter: Sendable {
    private let grammar: any TreeSitterExpressionGrammar

    init(grammar: any TreeSitterExpressionGrammar) {
        self.grammar = grammar
    }

    func count(body: Node) -> Int {
        var complexity = 1
        walk(body, into: &complexity)
        return complexity
    }

    private func walk(_ node: Node, into complexity: inout Int) {
        if grammar.isDecisionPoint(node) {
            complexity += 1
        }
        for child in node.namedChildren() {
            walk(child, into: &complexity)
        }
    }
}
