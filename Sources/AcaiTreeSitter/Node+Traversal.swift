public extension Node {

    /// Visits this node and every descendant in pre-order, including unnamed children.
    ///
    /// Iterative (explicit stack) so a tree nested thousands of levels deep — a generated or hostile
    /// file of nested parentheses, `if`s or chained calls — cannot overflow the thread's stack.
    func walkPreorder(_ visit: (Node) -> Void) {
        walk(children: { $0.children() }, visit: visit)
    }

    /// ``walkPreorder(_:)`` restricted to named children, for walks that read the grammar's own
    /// structure and must skip punctuation and keyword tokens.
    func walkNamedPreorder(_ visit: (Node) -> Void) {
        walk(children: { $0.namedChildren() }, visit: visit)
    }

    /// Children are pushed in reverse so the left-most is popped first, which is what makes the
    /// visit order pre-order rather than mirrored.
    private func walk(children: (Node) -> [Node], visit: (Node) -> Void) {
        var stack: [Node] = [self]
        while let node = stack.popLast() {
            visit(node)
            stack.append(contentsOf: children(node).reversed())
        }
    }
}
