public extension Node {

    /// Iterative, so a tree nested thousands of levels deep cannot overflow the stack.
    func walkPreorder(_ visit: (Node) -> Void) {
        walk(children: { $0.children() }, visit: visit)
    }

    func walkNamedPreorder(_ visit: (Node) -> Void) {
        walk(children: { $0.namedChildren() }, visit: visit)
    }

    /// Searches the whole subtree's named nodes in pre-order, stopping at the first match.
    func firstDescendant(withType type: String) -> Node? {
        var stack: [Node] = namedChildren().reversed()
        while let node = stack.popLast() {
            if node.nodeType == type { return node }
            stack.append(contentsOf: node.namedChildren().reversed())
        }
        return nil
    }

    /// Children are pushed in reverse so the left-most is popped first.
    private func walk(children: (Node) -> [Node], visit: (Node) -> Void) {
        var stack: [Node] = [self]
        while let node = stack.popLast() {
            visit(node)
            stack.append(contentsOf: children(node).reversed())
        }
    }
}
